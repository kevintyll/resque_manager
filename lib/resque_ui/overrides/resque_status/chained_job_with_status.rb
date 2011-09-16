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
end