require 'resque'
require 'resque/version'

class ResqueController < ApplicationController
  unloadable(self) #needed to prevent errors with authenticated system in dev env.

  layout 'resque'

  before_filter :check_connection

  verify :method => :post, :only => [:clear_failures, :clear_failure, :requeue_failure, :stop_worker, :restart_worker,
    :start_worker, :schedule_requeue, :remove_from_schedule, :add_scheduled_job, :start_scheduler, :stop_scheduler],
    :render => { :text => "<p>Please use the POST http method to post data to this API.</p>" }


  def index
    redirect_to(:action => 'overview')
  end

  def working
    render(:partial => 'working', :layout => 'resque')
  end

  def queues
    render(:partial => 'queues', :layout => 'resque', :locals => {:partial => nil})
  end

  def poll
    @polling = true
    render(:text => (render_to_string(:action => params[:page],:layout => false, :resque => Resque)).gsub(/\s{1,}/, ' '))
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

  def remove_job
    Resque.dequeue(params['class'].constantize,*params['args'])
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
      redirect_to(:action => 'stats',:id => 'resque')
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

      render(:text => stats.join("</br>"))
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
          'args' => Resque.decode(params['args']),
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
    Resque.redis.lrange(:scheduled,0,-1).each do |string|

      s = Resque.decode string

      if s[params['job_name']]
        Resque.redis.lrem(:scheduled, 0, string)
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

  private

  def check_connection
    Resque.keys
  rescue Errno::ECONNREFUSED
    render(:template => 'resque/error', :layout => false, :locals => {:error => "Can't connect to Redis! (#{Resque.redis.server})"})
    false
  end

  def remove_failure_from_list(payload)
    Resque.redis.lrange(:failed,0,-0).each do |string|

      f = Resque.decode string

      if f["payload"] == payload
        Resque.redis.lrem(:failed, 0, string)
      end
    end
  end

  def find_worker(worker)
    first_part, *rest = worker.split(':')
    first_part.gsub!(/_/,'.')
    Resque::Worker.find("#{first_part}:#{rest.join(':')}")
  end

end



#because of load order, this can't be in the resque_overrides file like it should be.
class Resque::Failure::Redis < Resque::Failure::Base
  def save
    data = {
      :failed_at => failed_at || Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
      :payload   => payload,
      :error     => exception.to_s,
      :backtrace => exception.backtrace,
      :worker    => worker.to_s,
      :queue     => queue
    }
    data = Resque.encode(data)
    Resque.redis.rpush(:failed, data)
  end
end