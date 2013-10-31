ResqueManager.configure do |config|
  config.redis_config = YAML.load(IO.read(Rails.root.join('config', 'redis.yml')))["#{Rails.env}_resque"]
  resque_manager_config = YAML.load(IO.read(Rails.root.join('config', 'resque_manager.yml')))[Rails.env]
  config.key_expiration = resque_manager_config['key_expiration']
  config.inline = resque_manager_config['inline']
  config.applications = resque_manager_config['applications']
end