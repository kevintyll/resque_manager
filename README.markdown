ResqueUi
--------

Resque UI is a Rails engine port of the Sinatra app that is included in Chris Wanstrath's resque gem.  We love the gem and love the UI,
but just didn't want to add Sinatra to our stack and wanted to be able to manage the queues from the UI.


Installation
------------

    sudo gem install resque_ui

Or just add it to your Gemfile

    gem 'resque_ui'

Once installed, you now have a resque controller, so you can get to the ui with:  http://your_domain/resque.

If you have your default routes disabled, which you should if you have a RESTful API, then you'll need to add this to
the top of your routes.rb file.

    # Resque UI
    map.connect 'resque/:action/:id', :controller => 'resque'


Dependencies
------------

This engine now requires rails 3.0.0 or greater.

This engine now requires redis 2.1.3 or greater for the expiration of keys to work correctly.

This engine requires the resque 1.5 or higher gem.

This engine now requires the resque-status 0.2.2 or higher gem.

This engine now requires the resque-cleaner 0.2.6 or higher gem.

These gems will all be installed for you automatically when you install resque_ui.


Times Fixed
-----------

The displaying of times is fixed.  Some browsers displayed "Nan days ago" for all process times in the original Sinatra app.
Fixed the stats/keys page.  The page wasn't showing the keys' types, size or values.

Display Process Status
----------------------

Added the ability to display process status in the worker "Processing" column on the workers and working pages.
To do this, yield the status message back in your perform method.  You should check that a block was sent. If you
set Resque.inline = true in development, then the block is not passed.

    Class YourClass

      self.perform(arg)
      ...your code here
      yield "Your status message" if block_given?
      ...more code
      yield "Another status message" if block_given?
      ...more code
      end
    end

This is really handy for those long running jobs to give you assurance the the job is really running or not.

![Status Messages](http://img.skitch.com/20100308-8mk5hrwnu462q2d23d51n8cjxp.png)

Restart Failed Jobs
-------------------

Added the Resque Cleaner gem to manage the failed queue.  Have complete control over the failed queue now with the
Cleaner tab by querying and restarting failed jobs.

See what all you can do on the github page:  https://github.com/ono/resque-cleaner

Remove Items from the Queue
---------------------------

Added the ability to remove jobs, from a queue

![Remove Items from the Queue](http://img.skitch.com/20100308-qukiw7bpsnr9y1saap7f8276qx.png)

View Processed Job Info
-----------------------

![Job Status](https://img.skitch.com/20110309-r9mhfgnn8w63ep29sik4c6khcj.png)

Resque_ui now incorporates the resque-status gem and replaced the Processed tab with the Status tab. You can read about
what you can do with resque-status [here](https://github.com/quirkey/resque-status).

I've added some additional functionality to the resque-status gem.  Namely, I've added a Resque::ChainedJobWithStatusClass.
We process a lot of data files.  Each part of the file's process is handled by a different worker.  One worker may convert
a file into a different format, then another will parse that file and peel each record off the file and put each individual
record on a separate queue.  A separate worker may then do any post processing when the file is complete.

I wanted all of that to show under a single status.  So to do that, the very first worker class inherits from
Resque::JobWithStatus, and everything after that inherits from Resque::ChainedJobWithStatus.  When you call #create on
the chained job from the preceding job, you just need to pass {'uuid' => uuid} as one of the hash arguments.

    class DataContributionFile < Resque::JobWithStatus
        @queue = :data_contribution

        def perform
            ...your code here
            tick "Retrieving file."
            ...more code
            tick "Peeling #{file_path}"
            SingleRecordLoader.create({'uuid' => uuid, 'row_data' => hash_of_row_data, 'rows_in_file' => total_rows})
        end
    end

    class SingleRecordLoader < Resque::ChainedJobWithStatus
        @queue = :single_record_loader

        def completed(*messages)
            if counter(:processed) >= options[:rows_in_file].to_i
            super("#{options[:rows_in_file]} records processed: Started(#{status.time.to_s(:eastern_time_zone_long)}) Finished(#{Time.now.to_s(:eastern_time_zone_long)})")
            post_process
        end

        def perform
            ...your code here

            incr_counter(:processed)
            at((self.processed), options[:rows_in_file], "#{(self.processed)} of #{options[:rows_in_file]} completed.")
        end
    end

So now, the data_contribution worker and the single_record_loader workers will update the same status on the status page.
You can call #tick or #set_status to add messages along the way too.

You will want to override the completed method so that it isn't called until the very end of the entire process.

I've also added two more methods, #incr_counter(:counter) and #count(:counter).  We have dozens of single_record_loader
workers processing records at a time.  You encounter a race condition when they are all calling #at at the same time to
update the :num attribute.  So I created these two methods to atomically increment a dedicated counter.  Just call #incr_counter
and pass in a symbol for what you want to call the counter.  You can create any number of different counters
for different purposes.  We keep track of different validation issues for each record.  Use #counter and pass is the same
symbol to read the integer back.  The redis entries created by these methods all get cleaned up with a call to Resque::Status.clear(uuid)

When you kill a job on the UI, it will kill all the workers in the chain.

Pause a Worker
--------------

The workers page now has a button for every worker to pause that worker.

### Regular Workers

For workers that do not inherit from JobWithStatus, this will pause the worker, but not the job.  So if the worker is in
the middle of a job when it is paused, it will finish it's process, but then will not pick anything else up off the queue.

You can manually pause the processing though.

yield, which is used to set the workers status, as described above, now returns the worker.

    Class YourClass

      self.perform(arg)
      ...your code here
      worker = yield "Your status message" if block_given?

      if worker && worker.paused?
          loop do
            break unless worker.paused?
            sleep 60
          end
        end
      end

      ...continue
    end

Remember to check that a block was sent. If you set Resque.inline = true in development, then the block is not passed.


### JobWithStatus Workers

For workers that do inherit from JobWithStatus or ChainedJobWithStatus, this will pause the worker, and will automatically pause the job it is processing
on the next call to #tick.  The worker is also available to JobWithStatus so you can manually check it's status as well.

    Class YourClass << Resque::JobWithStatus

    def perform
      ...your code here
      tick "Retrieving file."  #You're process with pause here automatically and the status on the Status tab will be set to paused if the worker is paused.

      #Alternatively, you have access to the worker, so you can pause the process yourself too.
      if worker && worker.paused?
          # There could be workers in a chained job still doing work.
          loop do
            pause! unless status.paused?
            break unless worker.paused?
            sleep 60
          end
          tick("Job resumed at #{Time.now}")
        end

      ...continue
    end

    This will only pause the work being processed by the worker that was paused.  If the job is paused by the call to #tick,
    the job will sleep for 60 seconds before checking the status again.

    You may have a series of ChainedJobWithStatus and you want all processing in the chain stopped.

    Class YourClass << Resque::ChainedJobWithStatus

    def perform
      ...your code here
      tick "Retrieving file."  #You're process with pause here automatically and the status on the Status tab will be set to paused if the worker is paused.

      #Alternatively, you have access to the worker, so you can pause the process yourself too.
      if (worker && worker.paused?) || status.paused?
          # There could be workers in a chained job still doing work.
          loop do
            pause! unless status.paused?
            break unless worker.paused?
            sleep 60
          end
          tick("Job resumed at #{Time.now}")
        end

      ...continue
    end

    By looking at the status.paused? method too, this process will stop, even if it's worker has not been paused.
    But be aware, if this worker does other jobs, it will not process anything else and it's queue could get backed up.
    This is where pausing one worker, could affect other, unrelated workers and jobs from getting backed up as well.

Throttle a Queue
----------------

A throttle method has been added.  This is useful if you have a queue that tends to have very high volume, for example,
the queue that process all the individual records of a file.  You don't want to load that queue up with 1 million entries,
possibly blowing out the memory of your Redis server.

    FasterCSV.foreach(self.file_path, :headers => true, :quote_char => '"') do |row|
        Resque.throttle(:single_record_loader, 10000, 30)
        SingleRecordLoader.create({'uuid' => uuid, 'row_data' => row.to_hash, 'rows_in_file' => total_rows})
    end

Putting the throttle before enqueing the SingleRecordLoader will check the single_record_loader queue to make sure it has
less than 10000 entries in it before proceeding.  If is has 10000 or more entries, it will sleep for 30 seconds before checking again.


Manage Workers
--------------

Added the ability to stop, start, and restart workers from the workers page.  This requires capistrano, and capistrano-ext to be installed on all
deployed servers.

![Manage Workers](http://img.skitch.com/20100308-ds6bgsnwqe6j9jn9yx8x7cxre3.png)


The controller calls cap tasks to manage the workers.  To include the recipes in your application, add this line to your deploy.rb file:

    require 'resque_ui/cap_recipes'

You will also need to define the :resque role in your deploy/<environment>.rb file with the servers that will run your workers.

    role :resque, 'server1', 'server2'

You will also need to make sure you have your rake path set in the deploy.rb file.

    set :rake, "/opt/ruby-enterprise-1.8.6-20090421/bin/rake"

You will also need to tell resque_ui where cap is installed.  Add this line to your environments.rb file:

    ResqueUi::Cap.path           = '/opt/ruby-enterprise-1.8.6-20090421/bin/cap'

...using your own path of course.

The cap tasks included are:

    cap resque:work                         # start a resque worker.
    cap resque:workers                      # start multiple resque workers.
    cap resque:quit_worker                  # Gracefully kill a worker.  If the worker is working, it will finish before shutting down.
    cap resque:quit_workers                 # Gracefully kill all workers on all servers.  If the worker is working, it will finish before shutting down.
    cap resque:kill_worker_with_impunity    # Kill a rogue worker.  If the worker is working, it will not finish and the job will go to the Failed queue as a DirtyExit. arg: host=ip pid=pid
    cap resque:kill_workera_with_impunity   # Kill all rogue workers on all servers.  If the worker is working, it will not finish and the job will go to the Failed queue as a DirtyExit.
    cap resque:restart_workers              # Restart all workers on all servers

Multi-Threaded Workers
---------------------
With Jruby, you have to specify the amount of memory to allocate when you start up the jvm.  This has proven inefficient for us because different workers
require different amounts of memory.  We have standardized our jvm configuration for the workers, which means we have to start each worker with
the maximum amount of memory needed by the most memory intensive worker.  This means we are wasting a lot of resources for the workers that don't
require as much memory.

Our answer was to make the workers multi-threaded.  Now you can pass multiple workers and queues into the rake task, each worker will be started in separate
threads within the same process.

NOTE:  The convention to identify which queues are monitored by which worker is to prefix each worker with a '#' in the rake task argument.

    rake QUEUE=#file_loader#file_loader,email resque:work

This will start up 2 workers, 1 will work the file_loader queue, and one will work the file_loader and email queue.

Be aware that when you stop a worker, it will stop all the workers within that process.

After Deploy Hooks
------------------

The resque:restart_workers cap task can be added as an after deploy task to refresh your workers.  Without this, your workers will
continue to run your old code base after a deployment.

To make it work add the callbacks in your deploy.rb file:

    after "deploy", "resque:restart_workers"
    after "deploy:migrations", "resque:restart_workers"


Resque Scheduler
----------------

If resque-scheduler is installed, the Schedule and Delayed tabs will display.

Be sure you add the resque_scheduler gem before the resque_ui gem in your Gemfile:

    gem 'resque-scheduler', :require => 'resque_scheduler'
    gem 'resque_ui'

The Schedule tab functionality has been enhanced to be able to add jobs to the scheduler from the UI.  This means you don't
need to edit a static file that gets loaded on initialization.  This also means you don't have to deploy that file every time
you edit your schedule.

You can also create different schedules on different servers in your farm.  You specify
the IP address you want to schedule a job to run on, and it will add the job to the schedule on that server.  You can also start and
stop the scheduler on each server from the Schedule tab.

![Resque Scheduler](http://img.skitch.com/20100308-quccysfiwtgubpw286ka2enr9m.png)

The caveat to this is the Arguments value must be entered in the text box as JSON in order for the arguments to get parsed and stored
in the schedule correctly.  I find the easiest thing to do is to perform a Resque.encode on my parameters list in script/console.  If
we have a method that takes 3 parameters:

    >> Resque.encode([['300'],1,{"start_date"=>"2010-02-01","end_date"=>"2010-02-28"}])
    => "[["300"],1,{"end_date":"2010-02-28","start_date":"2010-02-01"}]"

The first parameter is an array of strings, the second parameter is an integer, and the third parameter is a hash.
Remembering that the arguments are stored in an array, all the parameters need to be in an array when there is more than one.

Any string arguments need to be quoted in the text box:

    >> Resque.encode("Hello World")
    => ""Hello World""

### Additional cap tasks added:

    cap resque:quit_scheduler   # Gracefully kill the scheduler on a server.
    cap resque:scheduler        # start a resque worker.
    cap resque:scheduler_status # Determine if the scheduler is running or not

Delayed Tab
-----------

I have not tested or added any functionality to the Delayed tab.  I get a RuntimeError: -ERR invalid bulk write count
any time I try to do a Resque.enqueue_at.  I've spent some time researching, and assume it's something with my version combinations.
I believe it's a Redis issue and not a Resque-Scheduler issue.  But since I'm not using it, I haven't put a great deal of
time into resolving it.

Copyright (c) 2009 Chris Wanstrath
Copyright (c) 2010 Ben VandenBos
Copyright (c) 2010 Aaron Quint
Copyright (c) 2011 Tatsuya Ono
Copyright (c) 2010 Kevin Tyll, released under the MIT license

Thanks to Karl Baum for doing the original heavy lifting for converting this to a rails engine for rails 3.

Much thanks goes to Brian Ketelsen for the ideas for the improved functionality for the UI.
