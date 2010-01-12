require 'resque'
require 'resque/version'

class ResqueController < ApplicationController
  unloadable(self) #needed to prevent errors with authenticated system in dev env.

  layout 'resque'

  before_filter :check_connection

  verify :method => :post, :only => [:clear_failures, :clear_failure, :requeue_failure, :stop_worker, :restart_worker, :start_worker],
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
    remove_failure_from_list(params[:payload])
    redirect_to(:action => 'failed')
  end

  def requeue_failure
    #first clear the job we're restarting from the failure list.
    remove_failure_from_list(params[:payload])

    args = params["payload"]["args"]
    Resque.enqueue(eval(params["payload"]["class"]), *args)
    redirect_to(:action => 'failed')
  end

  def stop_worker
    server, pid, queues = params[:worker].split(':')
    kill_remote_pid(server, pid)
    redirect_to(:action => "workers")
  end

  def restart_worker
    server, pid, queues = params[:worker].split(':')
    kill_remote_pid(server, pid)
    ip = server[/\b(?:\d{1,3}\.){3}\d{1,3}\b/]
    start_remote_worker(ip, queues)
    redirect_to(:action => "workers")
  end

  def start_worker
    queues = params[:queues]
    ip = params[:hosts]
    start_remote_worker(ip, queues)
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

  private

  def check_connection
    Resque.keys
  rescue Errno::ECONNREFUSED
    render(:template => 'resque/error', :layout => false, :locals => {:error => "Can't connect to Redis! (#{Resque.redis.server})"})
    false
  end

  def remove_failure_from_list(payload)
    #we don't have a way of hand picking the job from the failure list,
    #so we must get the whole list, clear the list, then recreate the list
    #without the jobs that match the one we're restarting
    #VERY UGLY
    failures = Resque::Failure.all(0,Resque::Failure.count)
    failures = [failures] if Resque::Failure.count == 1
    failures.delete_if{|f| f["payload"] == payload}
    Resque::Failure.clear
    failures.each do |f|
      exception = Exception.new(f["error"])
      exception.set_backtrace(f["backtrace"])
      Resque::Failure.create(
        :payload   => f["payload"],
        :exception => exception,
        :worker    => f["worker"],
        :queue     => f["queue"],
        :failed_at => f["failed_at"])
    end
  end

  def kill_remote_pid(server, pid)
    if RAILS_ENV =~ /development|test/
      system("kill -QUIT  #{pid}")
    else
      ip = server[/\b(?:\d{1,3}\.){3}\d{1,3}\b/]
      system("cap #{RAILS_ENV} resque:quit_worker pid=#{pid} host=#{ip}")
    end
  end

  def start_remote_worker(ip, queues)
    if RAILS_ENV =~ /development|test/
      p1 = fork{system("rake QUEUE=#{queues} resque:work")}
      Process.detach(p1)
    else
      p1 = fork{system("cap #{RAILS_ENV} resque:work host=#{ip} queue=#{queues}")}
      Process.detach(p1)
    end
  end
end

#because of load order, this can't be in the resque_overrides file like it should be.
class Resque::Failure::Redis < Resque::Failure::Base
  def save
    data = {
      :failed_at => failed_at || Time.now.to_s,
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