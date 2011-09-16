namespace :resque do

  desc "Start a Resque worker, each queue will create it's own worker in a separate thread"
  task :work => :setup do
    require 'resque'

    worker                  = nil
    queues                  = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split('#').delete_if { |a| a.blank? }
    threads                 = []
    mqueue                  = queues.shift
    Thread.current[:queues] = mqueue
    mworker                 = Resque::Worker.new(mqueue)
    mworker.verbose         = true #ENV['LOGGING'] || ENV['VERBOSE']
    mworker.very_verbose    = true #ENV['VVERBOSE']

    if ENV['PIDFILE']
      File.open(ENV['PIDFILE'], 'w') { |f| f << mworker.pid }
    end

    queues.each do |queue|
      threads << Thread.new do
        begin
          Thread.current[:queues] = queue
          worker                  = Resque::Worker.new(queue)
          worker.verbose          = ENV['LOGGING'] || ENV['VERBOSE']
          worker.very_verbose     = ENV['VVERBOSE']
        rescue Resque::NoQueueError
          abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
        end

        worker.log "Starting worker #{worker}"
        begin
          worker.work(ENV['INTERVAL'] || 5) # interval, will block
        rescue Exception => e
          puts "********** e.message = " + e.message.inspect
          RAILS_DEFAULT_LOGGER.info "********** e.message = " + e.message.inspect
        end
      end
    end
    threads.each { |thread| thread.join(0.5) }
    mworker.work(ENV['INTERVAL'] || 5) # interval, will block
  end

  desc "Restart all the workers"
  task :restart_workers => :setup do
    require 'resque'
    pid = ''
    Resque.workers.sort_by { |w| w.to_s }.each do |worker|
      if pid != worker.pid
        worker.restart
        pid = worker.pid
      end
    end
  end

  desc "Gracefully kill all the workers.  If the worker is working, it will finish before shutting down. arg: host=ip pid=pid"
  task :quit_workers => :setup do
    require 'resque'
    pid = ''
    Resque.workers.sort_by { |w| w.to_s }.each do |worker|
      if pid != worker.pid
        worker.quit
        pid = worker.pid
      end
    end
  end

  desc "Kill all rogue workers on all servers.  If the worker is working, it will not finish and the job will go to the Failed queue as a DirtExit. arg: host=ip pid=pid"
  task :kill_workers_with_impunity => :setup do
    require 'resque'
    pid = ''
    Resque.workers.sort_by { |w| w.to_s }.each do |worker|
      if pid != worker.pid
        `kill -9 #{worker.pid}`
        pid = worker.pid
      end
    end
  end

end
