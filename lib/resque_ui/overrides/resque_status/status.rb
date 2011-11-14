module Resque
  class Status
    # The STATUSES constant is frozen, so we'll just manually add the paused? method here
    def paused?
        self['status'] === 'paused'
    end

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
      n = redis.incr(key)
      if expire_in
        redis.expire(key, expire_in)
      end
      n
    end
  end
end