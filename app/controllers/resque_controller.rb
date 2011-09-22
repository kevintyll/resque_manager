require 'resque'
require 'resque/version'
require 'digest/sha1'


class ResqueController < ApplicationController
  unloadable(self) #needed to prevent errors with authenticated system in dev env.

  layout 'resque'

  before_filter :check_connection

  before_filter :get_cleaner, :only => [:cleaner, :cleaner_exec, :cleaner_list, :cleaner_stale, :cleaner_dump]

  verify :method => :post, :only => [:clear_failures, :clear_failure, :requeue_failure, :stop_worker, :restart_worker,
                                     :start_worker, :schedule_requeue, :remove_from_schedule, :add_scheduled_job,
                                     :start_scheduler, :stop_scheduler, :requeue_failures_in_class,
                                     :kill, :clear_statuses, :cleaner_exec, :cleaner_stale],
         :render => {:text => "<p>Please use the POST http method to post data to this API.</p>".html_safe}


  def index
    redirect_to(:action => 'overview')
  end

  def working
    render('_working')
  end

  def queues
    render('_queues', :locals => {:partial => nil})
  end

  def poll
    @polling = true
    render(:text => (render_to_string(:action => "#{params[:page]}.html", :layout => false, :resque => Resque)).gsub(/\s{1,}/, ' '))
  end

  def status_poll
    @polling = true

    @start = params[:start].to_i
    @end = @start + (params[:per_page] || 20)
    @statuses = Resque::Status.statuses(@start, @end)
    @size = Resque::Status.status_ids.size

    render(:text => (render_to_string(:action => 'statuses.html', :layout => false)))
  end

  def remove_job
    Resque.dequeue(params['class'].constantize, *Resque.decode(params['args']))
    redirect_to request.referrer
  end

  def stop_worker
    worker = find_worker(params[:worker])
    worker.quit if worker
    redirect_to(:action => "workers")
  end

  def restart_worker
    worker = find_worker(params[:worker])
    worker.restart if worker
    redirect_to(:action => "workers")
  end

  def start_worker
    Resque::Worker.start(params[:hosts], params[:queues])
    redirect_to(:action => "workers")
  end

  def stats
    unless params[:id]
      redirect_to(:action => 'stats', :id => 'resque')
    end

    if params[:id] == 'txt'
      info = Resque.info

      stats = []
      stats << "resque.pending=#{info[:pending]}"
      stats << "resque.processed+=#{info[:processed]}"
      stats << "resque.failed+=#{info[:failed]}"
      stats << "resque.workers=#{info[:workers]}"
      stats << "resque.working=#{info[:working]}"

      Resque.queues.each do |queue|
        stats << "queues.#{queue}=#{Resque.size(queue)}"
      end

      render(:text => stats.join("</br>").html_safe)
    end
  end

  # resque-scheduler actions

  def schedule
    @farm_status = ResqueScheduler.farm_status
  end

  def schedule_requeue
    config = Resque.schedule[params['job_name']]
    Resque::Scheduler.enqueue_from_config(config)
    redirect_to(:action => 'overview')
  end

  def add_scheduled_job
    errors = []
    if Resque.schedule.keys.include?(params[:name])
      errors << 'Name already exists'
    end
    if params[:ip].blank?
      errors << 'You must enter an ip address for the server you want this job to run on.'
    end
    if params[:cron].blank?
      errors << 'You must enter the cron schedule.'
    end
    if errors.blank?
      config = {params['name'] => {'class' => params['class'],
                                   'ip' => params['ip'],
                                   'cron' => params['cron'],
                                   'args' => Resque.decode(params['args'].blank? ? nil : params['args']),
                                   'description' => params['description']}
      }
      Resque.redis.rpush(:scheduled, Resque.encode(config))
      ResqueScheduler.restart('ip')
    else
      flash[:error] = errors.join('<br>')
    end
    redirect_to(:action => 'schedule')
  end

  def remove_from_schedule
    Resque.list_range(:scheduled, 0, -0).each do |s|

      if s[params['job_name']]
        Resque.redis.lrem(:scheduled, 0, s.to_json)
        # Restart the scheduler on the server that has changed it's schedule
        ResqueScheduler.restart(params['ip'])
      end
    end
    redirect_to(:action => 'schedule')
  end

  def start_scheduler
    ResqueScheduler.start(params[:ip])
    redirect_to(:action => 'schedule')
  end

  def stop_scheduler
    ResqueScheduler.quit(params[:ip])
    redirect_to(:action => 'schedule')
  end

  # resque-status actions

  def statuses
    @start = params[:start].to_i
    @end = @start + (params[:per_page] || 20)
    @statuses = Resque::Status.statuses(@start, @end)
    @size = Resque::Status.status_ids.size
    if params[:format] == 'js'
      render :text => @statuses.to_json
    end
  end

  def clear_statuses
    Resque::Status.clear
    redirect_to(:action => 'statuses')
  end

  def status
    @status = Resque::Status.get(params[:id])
    if params[:format] == 'js'
      render :text => @status.to_json
    end
  end

  def kill
    Resque::Status.kill(params[:id])
    s = Resque::Status.get(params[:id])
    s.status = 'killed'
    Resque::Status.set(params[:id], s)
    redirect_to(:action => 'statuses')
  end

  def cleaner
    load_cleaner_filter

    @jobs = @cleaner.select
    @stats, @total = {}, {"total" => 0, "1h" => 0, "3h" => 0, "1d" => 0, "3d" => 0, "7d" => 0}
    @jobs.each do |job|
      klass = job["payload"]["class"]
      failed_at = Time.parse job["failed_at"]

      @stats[klass] ||= {"total" => 0, "1h" => 0, "3h" => 0, "1d" => 0, "3d" => 0, "7d" => 0}
      items = [@stats[klass], @total]

      items.each { |a| a["total"] += 1 }
      items.each { |a| a["1h"] += 1 } if failed_at >= hours_ago(1)
      items.each { |a| a["3h"] += 1 } if failed_at >= hours_ago(3)
      items.each { |a| a["1d"] += 1 } if failed_at >= hours_ago(24)
      items.each { |a| a["3d"] += 1 } if failed_at >= hours_ago(24*3)
      items.each { |a| a["7d"] += 1 } if failed_at >= hours_ago(24*7)
    end
  end

  def cleaner_list
    load_cleaner_filter

    block = filter_block

    @failed = @cleaner.select(&block).reverse

    url = "cleaner_list?c=#{@klass}&ex=#{@exception}&f=#{@from}&t=#{@to}"
    @dump_url = "cleaner_dump?c=#{@klass}&ex=#{@exception}&f=#{@from}&t=#{@to}"
    @paginate = Paginate.new(@failed, url, params[:p].to_i)

    @klasses = @cleaner.stats_by_class.keys
    @exceptions = @cleaner.stats_by_exception.keys
    @count = @cleaner.select(&block).size
  end

  def cleaner_exec
    load_cleaner_filter

    if params[:select_all_pages]!="1"
      @sha1 = {}
      params[:sha1].split(",").each { |s| @sha1[s] = true }
    end

    block = filter_block

    @count =
        case params[:form_action]
          when "clear" then
            @cleaner.clear(&block)
          when "retry_and_clear" then
            @cleaner.requeue(true, &block)
          when "retry" then
            @cleaner.requeue(false, {}, &block)
        end

    @link_url = "cleaner_list?c=#{@klass}&ex=#{@exception}&f=#{@from}&t=#{@to}"
  end

  def cleaner_dump
    load_cleaner_filter

    block = filter_block
    failures = @cleaner.select(&block)
    # pretty generate throws an error with the json gem on jruby
    output = JSON.pretty_generate(failures) rescue failures.to_json
    render :json => output
  end

  def cleaner_stale
    @cleaner.clear_stale
    redirect_to :action => "cleaner"
  end


  private

  def check_connection
    Resque.keys
  rescue Errno::ECONNREFUSED
    render(:template => 'resque/error', :layout => false, :locals => {:error => "Can't connect to Redis! (#{Resque.redis.server})"})
    false
  end

  def find_worker(worker)
    first_part, *rest = worker.split(':')
    first_part.gsub!(/_/, '.')
    Resque::Worker.find("#{first_part}:#{rest.join(':')}")
  end

  # resque-cleaner methods

  def get_cleaner
    @cleaner ||= Resque::Plugins::ResqueCleaner.new
    @cleaner.print_message = false
    @cleaner
  end

  def load_cleaner_filter
    @from = params[:f]=="" ? nil : params[:f]
    @to = params[:t]=="" ? nil : params[:t]
    @klass = params[:c]=="" ? nil : params[:c]
    @exception = params[:ex]=="" ? nil : params[:ex]
  end

  def filter_block
    block = lambda { |j|
      (!@from || j.after?(hours_ago(@from))) &&
          (!@to || j.before?(hours_ago(@to))) &&
          (!@klass || j.klass?(@klass)) &&
          (!@exception || j.exception?(@exception)) &&
          (!@sha1 || @sha1[Digest::SHA1.hexdigest(j.to_json)])
    }
  end

  def hours_ago(h)
    Time.now - h.to_i*60*60
  end

end

# Paginate class used by resque-cleaner

#Pagination helper for list page.
class Paginate
  attr_accessor :page_size, :page, :jobs, :url

  def initialize(jobs, url, page=1, page_size=20)
    @jobs = jobs
    @url = url
    @page = (!page || page < 1) ? 1 : page
    @page_size = 20
  end

  def first_index
    @page_size * (@page-1)
  end

  def last_index
    last = first_index + @page_size - 1
    last > @jobs.size-1 ? @jobs.size-1 : last
  end

  def paginated_jobs
    @jobs[first_index, @page_size]
  end

  def first_page?
    @page <= 1
  end

  def last_page?
    @page >= max_page
  end

  def page_url(page)
    u = @url
    u += @url.include?("?") ? "&" : "?"
    if page.is_a?(Symbol)
      page = @page - 1 if page==:prev
      page = @page + 1 if page==:next
    end
    u += "p=#{page}"
  end

  def total_size
    @jobs.size
  end

  def max_page
    ((total_size-1) / @page_size) + 1
  end
end