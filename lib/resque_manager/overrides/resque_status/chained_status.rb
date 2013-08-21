module Resque
  module Plugins
    module ChainedStatus

      def self.included(base)
        base.class_eval do
          include Resque::Plugins::Status
          extend ClassOverrides
          include InstanceOverrides
        end
      end

      module InstanceOverrides
        # OVERRIDE to just use the name of it's parent job.
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
      end

      module ClassOverrides
        # OVERRIDE to grab the uuid out of options so it can be chained to the calling worker
        # instead of creating a new uuid.
        def enqueue_to(queue, klass, options = {})
          #tie this job to the status of the calling job
          opts = HashWithIndifferentAccess.new(options)
          raise ArgumentError, "You must supply a :uuid attribute in your call to create." unless opts['uuid']
          uuid = opts['uuid']
          if Resque.enqueue_to(queue, klass, uuid, options)
            uuid
          else
            Resque::Plugins::Status::Hash.remove(uuid)
            nil
          end
        end
      end
    end
  end
end
