namespace :resque do

  desc "Requeue all failed jobs in a class.  If no class is given, all failed jobs will be requeued. ex: rake resque:requeue class=class_name"
  task :requeue => :setup do
    Resque::Failure.requeue ENV['class']
  end

end
