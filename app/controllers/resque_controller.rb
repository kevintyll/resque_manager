require 'resque'
require 'resque/version'

class ResqueController < ApplicationController
  unloadable(self) #needed to prevent errors with authenticated system in dev env.

  layout 'resque'

  before_filter :check_connection

  verify :method => :post, :only => [:clear_failures, :clear_failure, :requeue_failure, :stop_worker, :restart_worker,
                                     :start_worker, :schedule_requeue, :remove_from_schedule, :add_scheduled_job,
                                     :start_scheduler, :stop_scheduler, :requeue_failures_in_class,
                                     :kill, :clear_statuses],
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

  def failed
    if Resque::Failure.url
      redirect_to Resque::Failure.url
    end
  end

  def clear_failures
    Resque::Failure.clear
    redirect_to(:action => 'failed')
  end

  def clear_failure
    remove_failure_from_list(Resque.decode(params[:payload]))
    redirect_to(:action => 'failed')
  end

  def requeue_failure
    #first clear the job we're restarting from the failure list.
    payload = Resque.decode(params["payload"])
    remove_failure_from_list(payload)
    args = payload["args"]
    Resque.enqueue(eval(payload["class"]), *args)
    redirect_to(:action => 'failed')
  end

  def requeue_failures_in_class
    Resque::Failure.requeue_class(params['class'])
    redirect_to(:action => 'failed')
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

  private

  def check_connection
    Resque.keys
  rescue Errno::ECONNREFUSED
    render(:template => 'resque/error', :layout => false, :locals => {:error => "Can't connect to Redis! (#{Resque.redis.server})"})
    false
  end

  def remove_failure_from_list(payload)
    count = Resque::Failure.count - 1
    loop do
      f = Resque::Failure.all(count, 1)
      if f && f['payload'] == payload
        Resque.redis.lrem(:failed, 0, f.to_json)
      end
      count = count - 1
      break if count < 0
    end
  end

  def find_worker(worker)
    first_part, *rest = worker.split(':')
    first_part.gsub!(/_/, '.')
    Resque::Worker.find("#{first_part}:#{rest.join(':')}")
  end

end