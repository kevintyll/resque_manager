ResqueUi
--------

Resque UI is a Rails plugin port of the Sinatra app that is included in Chris Wanstrath's resque gem.  We love the gem and love the UI,
but just didn't want to add Sinatra to our stack and wanted to be able to manage the queues from the UI.


Installation
------------

script/plugin install git://github.com/kevintyll/resque_ui.git

Once installed, you now have a resque controller, so you can get to the ui with:  http://your_domain/resque.

Dependencies
------------

This plugin requires the resque 1.5 gem and of course the redis gem.

    sudo gem install resque

Times Fixed
-----------

The displaying of times is fixed.  Some browsers displayed "Nan days ago" for all process times in the original Sinatra app.
Fixed the stats/keys page.  The page wasn't showing the keys' types, size or values.

Display Process Status
----------------------

Added the ability to display process status in the worker "Processing" column on the workers and working pages.
To do this, yield the status message back in your perform method.

    Class YourClass

      self.perform(arg)
      ...your code here
      yield "Your status message"
      ...more code
      yield "Another status message"
      ...more code
      end
    end

This is really handy for those long running jobs to give you assurance the the job is really running or not.

![Status Messages](http://img.skitch.com/20100308-8mk5hrwnu462q2d23d51n8cjxp.png)

Restart Failed Jobs
-------------------

Added the ability to restart failed jobs, and clear individual failed jobs from the list

![Restart Failed Jobs](http://img.skitch.com/20100308-mbh5s8pcw5n4ei2hrseiqtshys.png)

Remove Items from the Queue
---------------------------

Added the ability to remove jobs, from a queue

![Remove Items from the Queue](http://img.skitch.com/20100308-qukiw7bpsnr9y1saap7f8276qx.png)

View Processed Job Info
-----------------------

A new tab has been added that shows custom information about jobs that have run.  You have to set that information yourself by calling:

    Resque::Job.process_info!(string)

Add this to the end of your perform method with any information you want displayed on the Processed tab in order to keep track of what has already
been processed.  We use the queues for a lot of different things including sending emails and processing data files.  I don't much care about what
emails have been sent, but I always want to know what files have been processed.  By adding the above line to my classes that process files, I now
have insight into what files have been processed.

I'm only keeping the last 100 records in the list.  I'm doing this so the page can be maintenance free, and I don't need a permanent history, just a
window to see what's recently been processed.


Manage Workers
--------------

Added the ability to stop, start, and restart workers from the workers page.  This requires capistrano, and capistrano-ext to be installed on all
deployed servers.

![Manage Workers](http://img.skitch.com/20100308-ds6bgsnwqe6j9jn9yx8x7cxre3.png)


The controller calls cap tasks to manage the workers.  To include the recipes in your application, add this line to your deploy.rb file:

    require File.dirname(__FILE__) + '/../vendor/plugins/resque_ui/lib/resque_ui/cap_recipes'

You will also need to make sure you have your rake path set in the deploy.rb file.

    set :rake, "/opt/ruby-enterprise-1.8.6-20090421/bin/rake"

You will also need to tell resque_ui where cap is installed.  Add this line to your environments.rb file:

    ResqueUi::Cap.path           = '/opt/ruby-enterprise-1.8.6-20090421/bin/cap'

...using your own path of course.

The cap tasks included are:

    cap resque:work          # start a resque worker.
    cap resque:workers       # start multiple resque workers.
    cap resque:quit_worker   # Gracefully kill a worker.  If the worker is working, it will finish before shutting down.
    cap resque:restart_workers # Restart all workers on all servers

Multi-Threaded Workers
---------------------
With Jruby, you have to specify the amount of memory to allocate when you start up the jvm.  This has proven inefficient for us because we workers
that require different amounts of memory.  We have standardized out jvm configuration for the workers, which means we have to start each worker with
the maximum amount of memory needed by the most memory intensive worker.  This means we are wasting a lot of resources for the workers that don't
require as much memory.

Our answer was to make the workers multi-threaded.  Now if you pass multiple queues into the rake task, each worker will be started in separate 
threads within the same process.

    rake QUEUE=file_loader,file_loader,email resque:work

This will start up 3 workers, 2 will work the file_loader queue, and one will work the email queue.  

Be aware that when you stop a worker, it will stop all the worker within that process.  Also be aware that this eliminates queue priority
since a separate worker is working each queue, rather than a list of queues.

After Deploy Hooks
------------------

The resque:restart_workers cap task can be added as an after deploy task to refresh your workers.  Without this, your workers will
continue to run your old code base after a deployment.

To make it work:
Set one of the servers in your app role as the resque_restart server:

    role :app, "your.first.ip.1","your.second.ip"
    role :app,  "your.first.ip.1", :resque_restart => true

Then add the callbacks:

    after "deploy", "resque:restart_workers"
    after "deploy:migrations", "resque:restart_workers"


Resque Scheduler
----------------

If resque-scheduler is installed, the Schedule and Delayed tabs will display.

The Schedule tab functionality has been enhanced to be able to add jobs to the schuduler from the UI.  This means you don't
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
any time I try to do a Resque.enqueu_at.  I've spent some time researching, and assume it's something with my version combinations.
I believe it's a Redis issue and not a Resque-Scheduler issue.  But since I'm not using it, I haven't put a great deal of
time into resolving it.

Copyright (c) 2009 Chris Wanstrath
Copyright (c) 2010 Ben VandenBos
Copyright (c) 2010 Kevin Tyll, released under the MIT license

Much thanks goes to Brian Ketelsen for the ideas for the improved functionality for the UI.
