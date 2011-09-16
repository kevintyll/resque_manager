require 'rake'
require 'rake/testtask'
require 'rdoc/task'
require 'yaml'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "resque_ui"
    gemspec.author = "Kevin Tyll"
    gemspec.email = "kevintyll@gmail.com"
    gemspec.homepage = %q{http://kevintyll.git.com/resque_ui}
    gemspec.summary = "A Rails engine port of the Sinatra app that is included in Chris Wanstrath's resque gem."
    gemspec.description = "A Rails UI for Resque for managing workers, failures and schedules."
  end

  Jeweler::GemcutterTasks.new

rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

desc 'Default: run unit tests.'
task :default => :test

desc 'Test the resque_ui engine.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the resque_ui engine.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  if File.exist?('VERSION.yml')
    config = YAML.load(File.read('VERSION.yml'))
    version = "#{config[:major]}.#{config[:minor]}.#{config[:patch]}"
  else
    version = ""
  end

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = "ResqueUi #{version}"
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('LICENSE*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
