require 'socket'

module Resque
  class Worker

    def local_ip
      orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true  # turn off reverse DNS resolution temporarily

      UDPSocket.open do |s|
        s.connect '64.233.187.99', 1
        s.addr.last
      end
    ensure
      Socket.do_not_reverse_lookup = orig
    end

    # The string representation is the same as the id for this worker
    # instance. Can be used with `Worker.find`.
    def to_s
      @to_s ||= "#{hostname}(#{local_ip}):#{Process.pid}:#{@queues.join(',')}"
    end
    alias_method :id, :to_s

    def pid
      to_s.split(':').second
    end

    def ip
      to_s.split(':').first[/\b(?:\d{1,3}\.){3}\d{1,3}\b/]
    end

    def queues
      to_s.split(':').last
    end

    # Looks for any workers which should be running on this server
    # and, if they're not, removes them from Redis.
    #
    # This is a form of garbage collection. If a server is killed by a
    # hard shutdown, power failure, or something else beyond our
    # control, the Resque workers will not die gracefully and therefor
    # will leave stale state information in Redis.
    #
    # By checking the current Redis state against the actual
    # environment, we can determine if Redis is old and clean it up a bit.
    def prune_dead_workers
      Worker.all.each do |worker|
        host, pid, queues = worker.id.split(':')
        next unless host.include?(hostname)
        next if worker_pids.include?(pid)
        log! "Pruning dead worker: #{worker}"
        worker.unregister_worker
      end
    end

    def status=(status)
      data = encode(job.merge('status' => status))
      redis.set("worker:#{self}", data)
    end

    def status
      job['status']
    end

    def self.start(ips, queues)
      if RAILS_ENV =~ /development|test/
        p1 = fork{system("rake QUEUE=#{queues} resque:work")}
        Process.detach(p1)
      else
        p1 = fork{system("#{ResqueUi::Cap.path} #{RAILS_ENV} resque:work host=#{ips} queue=#{queues}")}
        Process.detach(p1)
      end
    end

    def quit
      if RAILS_ENV =~ /development|test/
        system("kill -QUIT  #{self.pid}")
      else
        system("#{ResqueUi::Cap.path} #{RAILS_ENV} resque:quit_worker pid=#{self.pid} host=#{self.ip}")
      end
    end

    def restart
      quit
      self.class.start(self.ip, self.queues)
    end

  end



  class Job
    # Attempts to perform the work represented by this job instance.
    # Calls #perform on the class given in the payload with the
    # arguments given in the payload.
    # The worker is passed in so the status can be set for the UI to display.
    def perform
      args ? payload_class.perform(*args){|status| self.worker.status = status} : payload_class.perform{|status| self.worker.status = status}
    end

  end

  module Failure

    # Creates a new failure, which is delegated to the appropriate backend.
    #
    # Expects a hash with the following keys:
    #   :exception - The Exception object
    #   :worker    - The Worker object who is reporting the failure
    #   :queue     - The string name of the queue from which the job was pulled
    #   :payload   - The job's payload
    #   :failed_at - When the job originally failed.  Used when clearing a single failure  <<Optional>>
    def self.create(options = {})
      backend.new(*options.values_at(:exception, :worker, :queue, :payload, :failed_at)).save
    end

    # Requeues all failed jobs of a given class
    def self.requeue(failed_class)
      Resque.redis.lrange(:failed,0,-1).each do |string|

        f = Resque.decode string

        if f["payload"]["class"] == failed_class
          Resque.redis.lrem(:failed, 0, string)
        end
        args = f["payload"]["args"]
        Resque.enqueue(eval(f["payload"]["class"]), *args)
      end
    end

    class Base
      #When the job originally failed.  Used when clearing a single failure
      attr_accessor :failed_at

      def initialize(exception, worker, queue, payload, failed_at = nil)
        @exception = exception
        @worker    = worker
        @queue     = queue
        @payload   = payload
        @failed_at = failed_at
      end
    end

  end
end