namespace :resque do
  desc "Restart all the workers"
  task :restart_workers => :setup do
    require 'resque'
    Resque.workers.each do |worker|
      worker.restart
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
