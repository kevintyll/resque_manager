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
      `kill -QUIT #{pid}`
    end
  end

end
