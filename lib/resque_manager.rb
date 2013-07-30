require "resque_manager/engine"
require 'resque/server'
require 'resque_manager/overrides/resque/worker'
require 'resque_manager/overrides/resque/resque'
require 'resque_manager/overrides/resque/job'
require 'resque_manager/overrides/resque/failure/redis'
if Resque.respond_to? :schedule
  require 'resque_scheduler/tasks'
  require 'resque_manager/overrides/resque_scheduler/resque_scheduler'
end
require 'resque-status'
require 'resque_manager/overrides/resque_status/status'
require 'resque_manager/overrides/resque_status/chained_status'
require 'resque-cleaner'

Resque::Server.tabs << 'Statuses'
Resque::Server.tabs.delete 'Failed'

module ResqueManager
  # Set this to a hash of all the different applications and deployment paths
  # for those applications that have workers you want to manage.
  # The different app do not have to be deployed to the same server.
  # ex. {app1: 'www/var/rails/app1/current',
  #      app2: 'www/var/rails/app2/current'}
  # There is no need to set this if all the workers live in the same app as the Resque Manager
  # It will default to the current app's deploy path
  mattr_accessor :applications
  @@applicataions = nil

  mattr_accessor :redis_config
  @@redis_config = "SET TO RESQUE'S REDIS CONFIGURATION HASH"

  # Optionally set this to when you want to expire the resque keys.
  mattr_accessor :key_expiration
  @@key_expiration = nil

  # Optionally set this to determine whether to run inline or not.
  mattr_accessor :inline
  @@inline

  mattr_accessor :cap_path
  @@cap_path = 'REPLACE WITH THE PATH TO YOUR CAP INSTALLATION: ie. /opt/ruby-enterprise-1.8.6-20090421/bin/cap'

  def self.configure
    yield self
    Resque.redis = Redis.new(redis_config)
    Resque::Plugins::Status::Hash.expire_in = key_expiration
    Resque.inline = inline
  end
end
