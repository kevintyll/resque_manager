module Resque
  module Plugins
    module Status


      #OVERRIDE so we can add OverridesAndExtensionsClassMethods
      def self.included(base)
        attr_reader :worker

        # can't call super, so add ClassMethods here that resque-status was doing
        base.extend(ClassMethods) #add the methods in the resque-status gem
        base.extend(ClassOverridesAndExtensions)
      end

      module ClassOverridesAndExtensions
        # This is the method called by Resque::Worker when processing jobs. It
        # creates a new instance of the job class and populates it with the uuid and
        # options.
        #
        # You should not override this method, rather the <tt>perform</tt> instance method.
        # OVERRIDE to get the worker and set when initiaizing the class
        def perform(uuid=nil, options = {})
          uuid ||= Resque::Plugins::Status::Hash.generate_uuid
          worker = yield if block_given?
          instance = new(uuid, worker, options)
          instance.safe_perform!
          instance
        end

        # OVERRIDE to clear all the keys that have the UUI. status, counters, etc.
        def remove(uuid)
          Resque.redis.zrem(set_key, uuid)
          Resque.redis.keys("*#{uuid}").each do |key|
            Resque.redis.del(key)
          end
        end

        #If multiple workers are running at once and you need an incrementer, you can't use the status' num attribute because of race conditions.
        #You can use a counter and call incr on it instead
        def counter_key(counter, uuid)
          "#{counter}:#{uuid}"
        end

        def counter(counter, uuid)
          Resque.redis[counter_key(counter, uuid)].to_i
        end

        def incr_counter(counter, uuid)
          key = counter_key(counter, uuid)
          n = Resque.redis.incr(key)
          if Resque::Plugins::Status::Hash.expire_in
            Resque.redis.expire(key, Resque::Plugins::Status::Hash.expire_in)
          end
          n
        end
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

      # Run by the Resque::Worker when processing this job. It wraps the <tt>perform</tt>
      # method ensuring that the final status of the job is set regardless of error.
      # If an error occurs within the job's work, it will set the status as failed and
      # re-raise the error.
      #OVERRIDE to kill it.  The parent job may have been killed, so all child jobs should die as well.
      def safe_perform!
        k = should_kill?
        kill! if k
        unless k || (status && status.killed?)
          set_status({'status' => 'working'})
          perform
          if status && status.failed?
            on_failure(status.message) if respond_to?(:on_failure)
            return
          elsif status && !status.completed?
            completed
          end
          on_success if respond_to?(:on_success)
        end
      rescue Killed
        Rails.logger.info "Job #{self} Killed at #{Time.now}"
        Resque::Plugins::Status::Hash.killed(uuid)
        on_killed if respond_to?(:on_killed)
      rescue => e
        Rails.logger.error e
        failed("The task failed because of an error: #{e}")
        if respond_to?(:on_failure)
          on_failure(e)
        else
          raise e
        end
      end

      # sets a message for the job on the overview page
      # it can be set repeatedly durring the job's processing to
      # indicate the status of the job.
      def overview_message=(message)
        # there is no worker when run inline
        self.worker.overview_message = message if self.worker
      end

      def incr_counter(counter)
        self.class.incr_counter(counter, uuid)
      end

      def counter(counter)
        self.class.counter(counter, uuid)
      end

      # Return the <tt>num</tt> most recent status/job UUIDs in reverse chronological order.
      #override the gem to fix the ordering
      #def self.status_ids(range_start = nil, range_end = nil)
      #  unless range_end && range_start
      #    # Because we want a reverse chronological order, we need to get a range starting
      #    # by the higest negative number.
      #    Resque.redis.zrevrange(set_key, 0, -1) || []
      #  else
      #    # Because we want a reverse chronological order, we need to get a range starting
      #    # by the higest negative number. The ordering is transparent from the API user's
      #    # perspective so we need to convert the passed params
      #    if range_start == 0
      #      range_start = -1
      #    else
      #      range_start += 1
      #    end
      #    (Resque.redis.zrange(set_key, -(range_end.abs), -(range_start.abs)) || []).reverse
      #  end
      #end
    end
  end
end
