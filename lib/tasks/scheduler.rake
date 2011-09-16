namespace :resque do

  desc "Kill the scheduler pid"
  task :quit_scheduler => :setup do
    require 'resque_scheduler'
    ResqueScheduler.pids.each do |pid|
      `kill -TERM #{pid}`
    end
  end

end
