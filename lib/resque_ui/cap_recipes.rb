
# ====================================
# Resque TASKS
# ====================================


#You must set the path to your rake task in your deploy.rb file.
#ex.
# set :rake, "/opt/ruby-enterprise-1.8.6-20090421/bin/rake"
Capistrano::Configuration.instance(:must_exist).load do
  namespace :resque do
    desc "start a resque worker. optional arg: host=ip queue=name"
    task :work, :roles => :app do
      default_run_options[:pty] = true
      hosts = ENV['host'] || find_servers_for_task(current_task).collect{|s| s.host}
      queue = ENV['queue'] || '*'
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} QUEUE=#{queue} resque:work", :hosts => hosts)
    end

    desc "Gracefully kill a worker.  If the worker is working, it will finish before shutting down. arg: host=ip pid=pid"
    task :quit_worker, :roles => :app do
      if ENV['host'].nil? || ENV['host'].empty? || ENV['pid'].nil? || ENV['pid'].empty?
        puts 'You must enter the host and pid to kill..cap resque:quit host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect{|s| s.host}
        run("kill -HUP #{ENV['pid']}", :hosts => hosts)
      end
    end

    desc "start multiple resque workers. arg:count=x optional arg: host=ip queue=name"
    task :workers, :roles => :app do
      default_run_options[:pty] = true
      hosts = ENV['host'] || find_servers_for_task(current_task).collect{|s| s.host}
      queue = ENV['queue'] || '*'
      count = ENV['count'] || '1'
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} COUNT=#{count} QUEUE=#{queue} resque:work", :hosts => hosts)
    end

    desc "Restart all workers on all servers"
    task :restart_workers, :roles => :app, :only => { :resque_restart => true } do
      default_run_options[:pty] = true
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} resque:restart_workers")
    end

    # ====================================
    # ResqueScheduler TASKS
    # ====================================

    desc "start a resque worker. optional arg: host=ip queue=name"
    task :scheduler, :roles => :app do
      default_run_options[:pty] = true
      hosts = ENV['host'] || find_servers_for_task(current_task).collect{|s| s.host}
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} resque:scheduler", :hosts => hosts)
    end

    desc "Gracefully kill the scheduler on a server. arg: host=ip"
    task :quit_scheduler, :roles => :app do
      if ENV['host'].nil? || ENV['host'].empty?
        puts 'You must enter the host to kill..cap resque:quit_scheduler host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect{|s| s.host}
        rake = fetch(:rake, "rake")
        run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} resque:quit_scheduler", :hosts => hosts)
      end
    end

    desc "Determine if the scheduler is running or not on a server"
    task :scheduler_status, :roles => :app do
      hosts = ENV['hosts'].to_s.split(',') || find_servers_for_task(current_task).collect{|s| s.host}

      status = nil

      run("ps -eaf | grep resque | grep -v cap", :hosts => hosts)  do |channel, stream, data|
        status = (data =~ /resque:scheduler/) ? 'up' : 'down'
        puts " ** [#{stream} :: #{channel[:host]}] resque:scheduler is #{status}"
      end
    end
  end
end