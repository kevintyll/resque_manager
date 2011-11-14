# ====================================
# Resque TASKS
# ====================================


#You must set the path to your rake executable in your deploy.rb file.
#ex.
# set :rake, "/opt/ruby-enterprise-1.8.6-20090421/bin/rake"
#Optionally, you can set another variable, :resque_rake.  This will be used for the resque:work task if set.
#This allows you to set alternate options, particularly useful for jruby.
#ex.
#go through jexec so we get the right path and java settings
# set :rake, "script/jexec rake"
# set :resque_rake, "script/jexec -p rake" #extra memory settings for resque workers

#the jexec file in script/ may look like:

#scriptdir=`dirname $0`
#
## Hack to get things working under capistrano (used for torquebox to get rake working, still needed?)
#if [ "$1" = "-j" ]; then
#    shift
#    export JRUBY_HOME=$1
#    shift
#fi
#
#if [ "$1" = "-m" ]; then
#        shift
#        export JAVA_MEM="-Xmx2048m -Xms256m -XX:PermSize=1024m -XX:MaxPermSize=1024m"
#        export JAVA_STACK=-Xss4096k
#fi
#
#export PATH=$scriptdir:/opt/jruby/bin:$PATH
#
## Configuration settings for all Rake Tasks and Resque Workers
#if [ "$1" = "-p" ]; then
#        shift
#        # Set Heap Space for Young/Eden GC: 512MB
#        # Initial Heap size: 2GB
#        # Max Heap size: 4GB
#        # Use server JVM
#        # PermGenSize: 64MB
#        # Max PermGenSize: 128MB
#        # Thread Stack Size: 1024k
#        export JRUBY_OPTS="-J-Xmn512m -J-Xms2048m -J-Xmx4096m -J-server -J-XX:PermSize=64m -J-XX:MaxPermSize=128m -J-Xss1024k"
#        echo "JRUBY_OPTS=${JRUBY_OPTS}"
#        nohup $* & #cap task runs in background
#else
#        exec $*
#fi

Capistrano::Configuration.instance(:must_exist).load do

  def get_rake
    fetch(:resque_rake, fetch(:rake, "rake"))
  end

  namespace :resque do
    desc "start a resque worker. optional arg: host=ip queue=name"
    task :work, :roles => :resque do
      default_run_options[:pty] = true
      hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
      queue = ENV['queue'] || '*'
      rake = get_rake
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} QUEUE=#{queue} resque:work >> log/resque_worker.log 2>&1", :hosts => hosts)
    end

    desc "Gracefully kill a worker.  If the worker is working, it will finish before shutting down. arg: host=ip pid=pid"
    task :quit_worker, :roles => :resque do
      if ENV['host'].nil? || ENV['host'].empty? || ENV['pid'].nil? || ENV['pid'].empty?
        puts 'You must enter the host and pid to kill..cap resque:quit_worker host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
        if RUBY_PLATFORM =~ /java/
          #jruby doesn't trap the -QUIT signal
          #-TERM gracefully kills the main pid and does a -9 on the child if there is one.
          #Since jruby doesn't fork a child, the main worker is gracefully killed.
          run("kill -TERM #{ENV['pid']}", :hosts => hosts)
        else
          run("kill -QUIT #{ENV['pid']}", :hosts => hosts)
        end
      end
    end

    desc "Pause all workers in a single process. arg: host=ip pid=pid"
    task :pause_worker, :roles => :resque do
      if ENV['host'].nil? || ENV['host'].empty? || ENV['pid'].nil? || ENV['pid'].empty?
        puts 'You must enter the host and pid to kill..cap resque:pause_worker host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
        run("kill -USR2 #{ENV['pid']}", :hosts => hosts)
      end
    end

    desc "Continue all workers in a single process that have been paused. arg: host=ip pid=pid"
    task :continue_worker, :roles => :resque do
      if ENV['host'].nil? || ENV['host'].empty? || ENV['pid'].nil? || ENV['pid'].empty?
        puts 'You must enter the host and pid to kill..cap resque:continue_worker host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
        run("kill -CONT #{ENV['pid']}", :hosts => hosts)
      end
    end

    desc "Gracefully kill all workers on all servers.  If the worker is working, it will finish before shutting down."
    task :quit_workers, :roles => :resque do
      default_run_options[:pty] = true
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; #{rake} RAILS_ENV=#{stage} resque:quit_workers")
    end

    desc "Kill a rogue worker.  If the worker is working, it will not finish and the job will go to the Failed queue as a DirtyExit. arg: host=ip pid=pid"
    task :kill_worker_with_impunity, :roles => :resque do
      if ENV['host'].nil? || ENV['host'].empty? || ENV['pid'].nil? || ENV['pid'].empty?
        puts 'You must enter the host and pid to kill..cap resque:quit host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
        run("kill -9 #{ENV['pid']}", :hosts => hosts)
      end
    end

    desc "Kill all rogue workers on all servers.  If the worker is working, it will not finish and the job will go to the Failed queue as a DirtyExit."
    task :kill_workers_with_impunity, :roles => :resque do
      default_run_options[:pty] = true
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; #{rake} RAILS_ENV=#{stage} resque:kill_workers_with_impunity")
    end

    desc "start multiple resque workers. arg:count=x optional arg: host=ip queue=name"
    task :workers, :roles => :resque do
      default_run_options[:pty] = true
      hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
      queue = ENV['queue'] || '*'
      count = ENV['count'] || '1'
      rake = get_rake
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} COUNT=#{count} QUEUE=#{queue} resque:work >> log/resque_worker.log 2>&1", :hosts => hosts)
    end

    desc "Restart all workers on all servers"
    task :restart_workers, :roles => :resque do
      default_run_options[:pty] = true
      rake = fetch(:rake, "rake")
      #pass the rake options to the rake task so the workers can be started with the options.
      run("cd #{current_path}; RAILS_ENV=#{stage} RAKE_WITH_OPTS='#{get_rake}' nohup #{rake} resque:restart_workers")
    end

    # ====================================
    # ResqueScheduler TASKS
    # ====================================

    desc "start a resque worker. optional arg: host=ip queue=name"
    task :scheduler, :roles => :resque do
      default_run_options[:pty] = true
      hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
      rake = fetch(:rake, "rake")
      run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} resque:scheduler", :hosts => hosts)
    end

    desc "Gracefully kill the scheduler on a server. arg: host=ip"
    task :quit_scheduler, :roles => :resque do
      if ENV['host'].nil? || ENV['host'].empty?
        puts 'You must enter the host to kill..cap resque:quit_scheduler host=ip pid=pid'
      else
        hosts = ENV['host'] || find_servers_for_task(current_task).collect { |s| s.host }
        rake = fetch(:rake, "rake")
        run("cd #{current_path}; nohup #{rake} RAILS_ENV=#{stage} resque:quit_scheduler", :hosts => hosts)
      end
    end

    desc "Determine if the scheduler is running or not on a server"
    task :scheduler_status, :roles => :resque do
      hosts = ENV['hosts'].to_s.split(',') || find_servers_for_task(current_task).collect { |s| s.host }

      status = nil

      run("ps -eaf | grep resque | grep -v cap", :hosts => hosts) do |channel, stream, data|
        status = (data =~ /resque:scheduler/) ? 'up' : 'down'
        puts " ** [#{stream} :: #{channel[:host]}] resque:scheduler is #{status}"
      end
    end
  end
end