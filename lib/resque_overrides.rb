module Resque
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