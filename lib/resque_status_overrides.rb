module Resque

  class ChainedJobWithStatus < JobWithStatus
    def name
      status.name rescue nil
    end

    def completed(*messages)
      super(*messages)
      # "You must override this method to provide your own logic of when to actually call complete."
#      if counter(:processed) >= options['total']
#        super
#      end
    end

    def self.enqueue(klass, options = {})
      #tie this job to the status of the calling job
      opts = HashWithIndifferentAccess.new(options)
      raise ArgumentError, "You must supply a :uuid attribute in your call to create." unless opts['uuid']
      uuid = opts['uuid']
      Resque.enqueue(klass, uuid, options)
      uuid
    end
  end

  class JobWithStatus
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
    end

    # Run by the Resque::Worker when processing this job. It wraps the <tt>perform</tt>
    # method ensuring that the final status of the job is set regardless of error.
    # If an error occurs within the job's work, it will set the status as failed and
    # re-raise the error.
    def safe_perform!
      unless should_kill? || (status && status.killed?)
        set_status({'status' => 'working'})
        perform
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

  class Status
    # Return the <tt>num</tt> most recent status/job UUIDs in reverse chronological order.
    #override the gem to fix the ordering
    def self.status_ids(range_start = nil, range_end = nil)
      unless range_end && range_start
        # Because we want a reverse chronological order, we need to get a range starting
        # by the higest negative number.
        redis.zrevrange(set_key, 0, -1) || []
      else
        # Because we want a reverse chronological order, we need to get a range starting
        # by the higest negative number. The ordering is transparent from the API user's
        # perspective so we need to convert the passed params
        if range_start == 0
          range_start = -1
        else
          range_start += 1
        end
        (redis.zrange(set_key, -(range_end.abs), -(range_start.abs)) || []).reverse
      end
    end

    # clear statuses from redis passing an optional range. See `statuses` for info
    # about ranges
    def self.clear(range_start = nil, range_end = nil)
      status_ids(range_start, range_end).each do |id|
        redis.zrem(set_key, id)
        Resque.redis.keys("*#{id}").each do |key|
          Resque.redis.del(key)
        end
      end
    end

    #If multiple workers are running at once and you need an incrementer, you can't use the status' num attribute because of race conditions.
    #You can use a counter and call incr on it instead
    def self.counter_key(counter, uuid)
      "#{counter}:#{uuid}"
    end

    def self.counter(counter, uuid)
      redis[counter_key(counter, uuid)].to_i
    end

    def self.incr_counter(counter, uuid)
      key = counter_key(counter, uuid)
      redis.watch key
      saved = redis.multi do
        redis.incr(key)
        if expire_in
          redis.expire(key, expire_in)
        end
      end
      incr_counter(counter, uuid) unless saved
      saved.first
    end
  end
end