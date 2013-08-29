$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "resque_manager/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "resque_manager"
  s.version     = ResqueManager::VERSION
  s.authors     = ["Kevin Tyll"]
  s.email       = ["kevintyll@gmail.com"]
  s.homepage    = "https://github.com/kevintyll/resque_manager"
  s.summary     = "A Rails UI for Resque for managing workers, failures and schedules."
  s.summary     = "A Rails engine port of the Sinatra app that is included in Chris Wanstrath's resque gem."

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.markdown"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 3.2"
  s.add_dependency  'redis', "~> 3.0"
  s.add_dependency  'resque', "~> 1.24"
  s.add_dependency  'resque-status', "~> 0.4"
  s.add_dependency  'resque-cleaner', "~> 0.2"
  s.add_dependency  'jquery-rails'

  s.license = 'MIT'

end
