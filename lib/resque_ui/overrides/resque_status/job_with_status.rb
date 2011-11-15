module Resque
  class JobWithStatus

    attr_reader :worker

    # Adds a job of type <tt>klass<tt> to the queue with <tt>options<tt>.
    # Returns the UUID of the job
    # override to pass actual parameters instead of a single hash, to make backward compatible with existing resque jobs.
    def self.enqueue(klass, options = {})
      uuid = Resque::Status.create :name => "#{self.name}: #{options.inspect}"
      Resque.enqueue(klass, uuid, options)
      uuid
    end

    # sets the status of the job for the current iteration. You should use
    # the <tt>at</tt> method if you have actual numbers to track the iteration count.
    # This will kill the job if it has been added to the kill list with
    # <tt>Resque::Status.kill()</tt>
    def tick(*messages)
      kill! if should_kill? || status.killed?
      set_status({'status' => 'working'}, *messages)
      # check to see if the worker doing the job has been paused, pause the job if so
      if self.worker && self.worker.paused?
        loop do
          # Set the status to paused.
          # May need to do this repeatedly because there could be workers in a chained job still doing work.
          pause! unless status.paused?
          break unless self.worker.paused?
          sleep 60
        end
        set_status({'status' => 'working'}, *messages) unless status && (status.completed? || status.paused? || status.killed?)
      end
    end

    # Pause the current job, setting the status to 'paused'
    def pause!
      set_status({
                     'status' => 'paused',
                     'message' => "#{worker} paused at #{Time.now}"
                 })
    end

    # Create a new instance with <tt>uuid</tt> and <tt>options</tt>
    # OVERRIDE to add the worker attr
    def initialize(uuid, worker = nil, options = {})
      @uuid = uuid
      @options = options
      @worker = worker
    end

    # This is the method called by Resque::Worker when processing jobs. It
    # creates a new instance of the job class and populates it with the uuid and
    # options.
    #
    # You should not override this method, rather the <tt>perform</tt> instance method.
    # OVERRIDE to pass the block in order to set the worker status, returns the worker object
    def self.perform(uuid=nil, options = {})
      uuid ||= Resque::Status.generate_uuid
      worker = yield if block_given?
      instance = new(uuid, worker, options)
      instance.safe_perform! { |status| yield status if block_given? }
      instance
    end

    # Run by the Resque::Worker when processing this job. It wraps the <tt>perform</tt>
    # method ensuring that the final status of the job is set regardless of error.
    # If an error occurs within the job's work, it will set the status as failed and
    # re-raise the error.
    def safe_perform!
      unless should_kill? || (status && status.killed?)
        set_status({'status' => 'working'})
        perform { |status| yield status if block_given?  }
        kill! if should_kill?
        completed unless status && status.completed?
        on_success if respond_to?(:on_success)
      end
    rescue Killed
      logger.info "Job #{self} Killed at #{Time.now}"
      Resque::Status.killed(uuid)
      on_killed if respond_to?(:on_killed)
    rescue => e
      logger.error e
      failed("The task failed because of an error: #{e}")
      if respond_to?(:on_failure)
        on_failure(e)
      else
        raise e
      end
    end

    def name
      "#{self.class.name}: #{options.inspect}"
    end

    def incr_counter(counter)
      Resque::Status.incr_counter(counter, uuid)
    end

    def counter(counter)
      Resque::Status.counter(counter, uuid)
    end
  end
end