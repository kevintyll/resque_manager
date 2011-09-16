module Resque
  class Job
    # Attempts to perform the work represented by this job instance.
    # Calls #perform on the class given in the payload with the
    # arguments given in the payload.
    # The worker is passed in so the status can be set for the UI to display.
    def perform
      args ? payload_class.perform(*args) { |status| self.worker.status = status } : payload_class.perform { |status| self.worker.status = status }
    end

  end
end