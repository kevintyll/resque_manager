require 'resque/server'
require 'resque_ui/cap'
require 'resque_ui/overrides/resque/worker'
require 'resque_ui/overrides/resque/resque'
require 'resque_ui/overrides/resque/job'
if Resque.respond_to? :schedule
  require 'resque_scheduler/tasks'
  require 'resque_ui/overrides/resque_scheduler/resque_scheduler'
end
require 'resque/job_with_status'
require 'resque_ui/overrides/resque_status/status'
require 'resque_ui/overrides/resque_status/job_with_status'
require 'resque_ui/overrides/resque_status/chained_job_with_status'
require 'resque-cleaner'

Resque::Server.tabs << 'Statuses'
Resque::Server.tabs.delete 'Failed'

module ResqueUi
  class Engine < Rails::Engine
  end
end