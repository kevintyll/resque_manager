require 'resque/failure/redis'

module Resque
  module Failure

    # Requeues all failed jobs of a given class
    def self.requeue_class(failed_class)
      length = Resque.redis.llen(:failed)
      i = 0
      length.times do
        f = Resque.list_range(:failed, i, 1)
        if f && (failed_class.blank? || (f["payload"]["class"] == failed_class))
          Resque.redis.lrem(:failed, 0, f.to_json)
          args = f["payload"]["args"]
          Resque.enqueue(eval(f["payload"]["class"]), *args)
        else
          i += 1
        end
      end
    end
  end
end