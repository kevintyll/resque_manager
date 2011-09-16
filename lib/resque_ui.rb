require 'resque/server'
require 'resque_ui/cap'
require 'resque_ui/overrides/resque/worker'
require 'resque_ui/overrides/resque/resque'
require 'resque_ui/overrides/resque/job'
require 'resque_ui/overrides/resque/failure/failure'
if Resque.respond_to? :schedule
  require 'resque_scheduler/tasks'
  require 'resque_ui/overrides/resque_scheduler/resque_scheduler'
end
require 'resque/job_with_status'
require 'resque_ui/overrides/resque_status/status'
require 'resque_ui/overrides/resque_status/job_with_status'
require 'resque_ui/overrides/resque_status/chained_job_with_status'

Resque::Server.tabs << 'Statuses'

module ResqueUi
  class Engine < Rails::Engine
    rake_tasks do
      load 'tasks/worker.rake'
      load 'tasks/failure.rake'
      load 'tasks/scheduler.rake' if Resque.respond_to? :schedule
    end
  end
end