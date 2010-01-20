namespace :resque do
  desc "Restart all the workers"
  task :restart_workers => :setup do
    require 'resque'
    Resque.workers.each do |worker|
      worker.restart
    end
  end
end
