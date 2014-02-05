require 'socket'
require 'semantic_logger'

module Resque
  class Worker
    include SemanticLogger::Loggable

    @@local_ip = nil

    def local_ip
      @@local_ip ||= IPSocket.getaddress(Socket.gethostname)
    end

    # The string representation is the same as the id for this worker
    # instance. Can be used with `Worker.find`.
    def to_s
      @to_s || "#{hostname}(#{local_ip}):#{Process.pid}:#{Thread.current.object_id}:#{Thread.current[:path]}:#{Thread.current[:queues]}"
    end

    alias_method :id, :to_s

    # When the worker gets the -USR2 signal, to_s may give a different value for the thread and queue portion
    def pause_key
      key = to_s.split(':')
      "worker:#{key.first}:#{key.second}:all_workers:paused"
    end

    def pid
      to_s.split(':').second
    end

    def thread
      to_s.split(':').third
    end

    def path
      to_s.split(':').fourth
    end

    def queue
      to_s.split(':').fifth
    end

    def workers_in_pid
      Array(Resque.redis.smembers(:workers)).select { |id| id =~ /\(#{ip}\):#{pid}/ }.map { |id| Resque::Worker.find(id) }.compact
    end

    def ip
      to_s.split(':').first[/\b(?:\d{1,3}\.){3}\d{1,3}\b/]
    end

    def queues_in_pid
      workers_in_pid.collect { |w| w.queue }.compact
    end

    #OVERRIDE for multithreaded workers
    def queues
      Thread.current[:queues] == "*" ? Resque.queues.sort : Thread.current[:queues].split(',')
    end

    # Runs all the methods needed when a worker begins its lifecycle.
    #OVERRIDE for multithreaded workers
    def startup
      enable_gc_optimizations
      if Thread.current == Thread.main
        register_signal_handlers
        prune_dead_workers
      end
      run_hook :before_first_fork
      register_worker

      # Fix buffering so we can `rake resque:work > resque.log` and
      # get output from the child in there.
      $stdout.sync = true
    end

    # Schedule this worker for shutdown. Will finish processing the
    # current job.
    #OVERRIDE for multithreaded workers
    def shutdown_with_multithreading
      Thread.list.each { |t| t[:shutdown] = true }
      shutdown_without_multithreading
    end
    alias_method_chain :shutdown, :multithreading

    def paused
      Resque.redis.get pause_key
    end

    # are we paused?
    # OVERRIDE so UI can tell if we're paused
    def paused?
      @paused || paused.present?
    end

    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    #OVERRIDE to set a redis key so UI knows it's paused too
    def pause_processing_with_pause_key
      pause_processing_without_pause_key
      Resque.redis.set(pause_key, Time.now.to_s)
    end
    alias_method_chain :pause_processing, :pause_key

    # Start processing jobs again after a pause
    #OVERRIDE to set remove redis key so UI knows it's unpaused too
    # Would prefer to call super but get no superclass method error
    def unpause_processing_with_pause_key
      unpause_processing_without_pause_key
      Resque.redis.del(pause_key)
    end
    alias_method_chain :unpause_processing, :pause_key

    # Looks for any workers which should be running on this server
    # and, if they're not, removes them from Redis.
    #
    # This is a form of garbage collection. If a server is killed by a
    # hard shutdown, power failure, or something else beyond our
    # control, the Resque workers will not die gracefully and therefore
    # will leave stale state information in Redis.
    #
    # By checking the current Redis state against the actual
    # environment, we can determine if Redis is old and clean it up a bit.
    def prune_dead_workers
      Worker.all.each do |worker|
        host, pid, thread, path, queues = worker.id.split(':')
        next unless host.include?(hostname)
        next if worker_pids.include?(pid)
        log! "Pruning dead worker: #{worker}"
        worker.unregister_worker
      end
    end

    # Unregisters ourself as a worker. Useful when shutting down.
    # OVERRIDE to also remove the pause key
    # Would prefer to call super but get no superclass method error
    def unregister_worker_with_pause(exception = nil)
      unregister_worker_without_pause(exception)

      Resque.redis.del(pause_key)
    end
    alias_method_chain :unregister_worker, :pause

    def all_workers_in_pid_working
      workers_in_pid.select { |w| (hash = w.processing) && !hash.empty? }
    end

    # This is the main workhorse method. Called on a Worker instance,
    # it begins the worker life cycle.
    #
    # The following events occur during a worker's life cycle:
    #
    # 1. Startup:   Signals are registered, dead workers are pruned,
    #               and this worker is registered.
    # 2. Work loop: Jobs are pulled from a queue and processed.
    # 3. Teardown:  This worker is unregistered.
    #
    # Can be passed an integer representing the polling frequency.
    # The default is 5 seconds, but for a semi-active site you may
    # want to use a smaller value.
    #
    # Also accepts a block which will be passed the job as soon as it
    # has completed processing. Useful for testing.
    #OVERRIDE for multithreaded workers
    def work_with_multithreading(interval = 5.0, &block)
      work_without_multithreading(interval, &block)
      loop do
        #hang onto the process until all threads are done
        break if all_workers_in_pid_working.blank?
        sleep interval.to_i
      end
    end
    alias_method_chain :work, :multithreading

    def shutdown_with_multithreading?
      shutdown_without_multithreading? || Thread.current[:shutdown]
    end
    alias_method_chain :shutdown?, :multithreading

    # logic for mappged_mget changed where it returns keys with nil values in latest redis gem.
    def self.working
      names = all
      return [] unless names.any?
      names.map! { |name| "worker:#{name}" }
      Resque.redis.mapped_mget(*names).map do |key, value|
        find key.sub("worker:", '') unless value.nil?
      end.compact
    end

    def overview_message=(message)
      data = encode(job.merge('overview_message' => message))
      Resque.redis.set("worker:#{self}", data)
    end

    def overview_message
      job['overview_message']
    end

    def self.start(options)
      ips = options[:hosts]
      application_path = options[:application_path]
      queues = options[:queues]
      if Rails.env =~ /development|test/
        Thread.new(application_path, queues) { |application_path, queue| system("cd #{application_path || '.'} && bundle exec #{ResqueManager.resque_worker_rake || 'rake'} RAILS_ENV=#{Rails.env} QUEUE=#{queue} resque:work") }
      else
        Thread.new(ips, application_path, queues) { |ip_list, application_path, queue| system("cd #{Rails.root} && bundle exec cap #{Rails.env} resque:work host=#{ip_list} application_path=#{application_path} queue=#{queue}") }
      end
    end

    def quit
      if Rails.env =~ /development|test/
        if RUBY_PLATFORM =~ /java/
          #jruby doesn't trap the -QUIT signal
          #-TERM gracefully kills the main pid and does a -9 on the child if there is one.
          #Since jruby doesn't fork a child, the main worker is gracefully killed.
          system("kill -TERM  #{self.pid}")
        else
          system("kill -QUIT  #{self.pid}")
        end
      else
        system("cd #{Rails.root} && bundle exec cap #{Rails.env} resque:quit_worker pid=#{self.pid} host=#{self.ip} application_path=#{self.path}")
      end
    end

    def pause
      if Rails.env =~ /development|test/
        system("kill -USR2  #{self.pid}")
      else
        system("cd #{Rails.root} && bundle exec cap #{Rails.env} resque:pause_worker pid=#{self.pid} host=#{self.ip}")
      end
    end

    def continue
      if Rails.env =~ /development|test/
        system("kill -CONT  #{self.pid}")
      else
        system("cd #{Rails.root} && bundle exec cap #{Rails.env} resque:continue_worker pid=#{self.pid} host=#{self.ip}")
      end
    end

    def restart
      queues = self.queues_in_pid.join('#')
      quit
      self.class.start(hosts: self.ip, queues: queues, application_path: self.path)
    end

  end
end
