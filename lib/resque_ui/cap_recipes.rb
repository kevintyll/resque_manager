
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
        run("kill -QUIT #{ENV['pid']}", :hosts => hosts)
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

  end
end