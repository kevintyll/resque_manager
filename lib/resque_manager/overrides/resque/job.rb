module Resque
  class Job
    # Attempts to perform the work represented by this job instance.
    # Calls #perform on the class given in the payload with the
    # arguments given in the payload.
    # A block is sent so a message can be yielded back to be set in the worker.
    def perform
      job = payload_class
      job_args = args || []
      job_was_performed = false

      begin
        # Execute before_perform hook. Abort the job gracefully if
        # Resque::DontPerform is raised.
        begin
          before_hooks.each do |hook|
            job.send(hook, *job_args)
          end
        rescue DontPerform
          return false
        end

        # Execute the job. Do it in an around_perform hook if available.
        if around_hooks.empty?
          job.perform(*job_args) do |status|
            self.worker
          end
          job_was_performed = true
        else
          # We want to nest all around_perform plugins, with the last one
          # finally calling perform
          stack = around_hooks.reverse.inject(nil) do |last_hook, hook|
            if last_hook
              lambda do
                job.send(hook, *job_args) { last_hook.call }
              end
            else
              lambda do
                job.send(hook, *job_args) do
                  result = job.perform(*job_args) do |status|
                    self.worker
                  end
                  job_was_performed = true
                  result
                end
              end
            end
          end
          stack.call
        end

        # Execute after_perform hook
        after_hooks.each do |hook|
          job.send(hook, *job_args)
        end

        # Return true if the job was performed
        return job_was_performed

          # If an exception occurs during the job execution, look for an
          # on_failure hook then re-raise.
      rescue Object => e
        failure_hooks.each { |hook| job.send(hook, e, *job_args) }
        raise e
      end
    end

  end
end