namespace :resque do

  desc "Start a Resque worker, each queue will create it's own worker in a separate thread"
  task :work => :setup do
    require 'resque'

    worker = nil
    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')
    threads = []
    mqueue = queues.shift
    Thread.current[:queue] = mqueue
    mworker = Resque::Worker.new(mqueue)
    mworker.verbose = true #ENV['LOGGING'] || ENV['VERBOSE']
    mworker.very_verbose = true #ENV['VVERBOSE']

    queues.each do |queue|
      threads << Thread.new do
        begin
          Thread.current[:queue] = queue
          worker = Resque::Worker.new(queue)
          worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
          worker.very_verbose = ENV['VVERBOSE']
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
    threads.each {|thread| thread.join(0.5) }
  end

  desc "Restart all the workers"
  task :restart_workers => :setup do
    require 'resque'
    pid = ''
    Resque.workers.each do |worker|
      if pid != worker.pid
        worker.restart
        pid = worker.pid
      end
    end
  end

  desc "Kill the scheduler pid"
  task :quit_scheduler => :setup do
    require 'resque_scheduler'
    ResqueScheduler.pids.each do |pid|
      `kill -TERM #{pid}`
    end
  end

  desc "Requeue all failed jobs in a class.  If no class is given, all failed jobs will be requeued. ex: rake resque:requeue class=class_name"
  task :requeue => :setup do
    Resque::Failure.requeue ENV['class']
  end

end
