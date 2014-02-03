# Only load this file if it's running from the server, not from a rake task starting a worker.  Workers don't need the controller.
unless defined?($rails_rake_task) && $rails_rake_task
  require 'resque'
  require 'resque/version'
  require 'digest/sha1'


  module ResqueManager
    class ResqueController < ApplicationController
      unloadable(self) #needed to prevent errors with authenticated system in dev env.

      layout 'resque_manager/application'

      before_filter :check_connection

      before_filter :get_cleaner, :only => [:cleaner, :cleaner_exec, :cleaner_list, :cleaner_stale, :cleaner_dump]

      def working
        render('_working')
      end

      def queues
        render('_queues', :locals => {:partial => nil})
      end

      def poll
        @polling = true
        render(:text => (render_to_string(:action => "#{params[:page]}", :formats => [:html], :layout => false, :resque => Resque)).gsub(/\s{1,}/, ' '))
      end

      def status_poll
        @polling = true

        @start = params[:start].to_i
        @end = @start + (params[:per_page] || 20)
        @statuses = Resque::Plugins::Status::Hash.statuses(@start, @end) rescue []
        @size = Resque::Plugins::Status::Hash.status_ids.size

        render(:text => (render_to_string(:action => 'statuses', :formats => [:html], :layout => false)))
      end

      def remove_job
        # We can only dequeue a job when that job is in the same application as the UI.
        # Otherwise we get an error when we try to constantize a class that does not exist
        # in the application the UI is in.
        if ResqueManager.applications.blank?
          Resque.dequeue(params['class'].constantize, *Resque.decode(params['args']))
        end
        redirect_to request.referrer
      end

      def stop_worker
        worker = find_worker(params[:worker])
        worker.quit if worker
        redirect_to workers_resque_path
      end

      def pause_worker
        worker = find_worker(params[:worker])
        worker.pause if worker
        redirect_to workers_resque_path
      end

      def continue_worker
        worker = find_worker(params[:worker])
        worker.continue if worker
        redirect_to workers_resque_path
      end

      def restart_worker
        worker = find_worker(params[:worker])
        worker.restart if worker
        redirect_to workers_resque_path
      end

      def start_worker
        Resque::Worker.start(params)
        redirect_to workers_resque_path
      end

      def stats
        unless params[:id]
          redirect_to(stats_resque_path(:id => 'resque'))
        end

        if params[:id] == 'txt'
          info = Resque.info

          stats = []
          stats << "resque.pending=#{info[:pending]}"
          stats << "resque.processed+=#{info[:processed]}"
          stats << "resque.failed+=#{info[:failed]}"
          stats << "resque.workers=#{info[:workers]}"
          stats << "resque.working=#{info[:working]}"
          Resque.queues.each do |queue|
            stats << "queues.#{queue}=#{Resque.size(queue)}"
          end

          render(:text => stats.join("</br>").html_safe)
        end
      end

      # resque-scheduler actions

      def schedule
        @farm_status = ResqueScheduler.farm_status
      end

      def schedule_requeue
        config = Resque.schedule[params['job_name']]
        Resque::Scheduler.enqueue_from_config(config)
        redirect_to overview_resque_path
      end

      def add_scheduled_job
        errors = []
        if Resque.schedule.keys.include?(params[:name])
          errors << 'Name already exists.'
        end
        if params[:ip].blank?
          errors << 'You must enter an ip address for the server you want this job to run on.'
        end
        if params[:cron].blank?
          errors << 'You must enter the cron schedule.'
        end
        if errors.blank?
          config = {params['name'] => {'class' => params['class'],
                                       'ip' => params['ip'],
                                       'cron' => params['cron'],
                                       'args' => Resque.decode(params['args'].blank? ? nil : params['args']),
                                       'description' => params['description']}
          }
          Resque.redis.rpush(:scheduled, Resque.encode(config))
          ResqueScheduler.restart(params['ip'])
        else
          flash[:error] = errors.join('<br>').html_safe
        end
        redirect_to schedule_resque_path
      end

      def remove_from_schedule
        Resque.list_range(:scheduled, 0, -0).each do |s|
          if s[params['job_name']]
            Resque.redis.lrem(:scheduled, 0, s.to_json)
            # Restart the scheduler on the server that has changed it's schedule
            ResqueScheduler.restart(params['ip'])
          end
        end
        redirect_to schedule_resque_path
      end

      def start_scheduler
        ResqueScheduler.start(params[:ip])
        redirect_to schedule_resque_path
      end

      def stop_scheduler
        ResqueScheduler.quit(params[:ip])
        redirect_to schedule_resque_path
      end

      # resque-status actions

      def statuses
        @start = params[:start].to_i
        @end = @start + (params[:per_page] || 20)
        @statuses = Resque::Plugins::Status::Hash.statuses(@start, @end)
        @size = Resque::Plugins::Status::Hash.status_ids.size
        respond_to do |format|
          format.js { render json: @statuses }
          format.html { render :statuses }
        end
      end

      def clear_statuses
        Resque::Plugins::Status::Hash.clear
        redirect_to statuses_resque_path
      end

      def status
        @status = Resque::Plugins::Status::Hash.get(params[:id])
        respond_to do |format|
          format.js { render json: @status }
          format.html { render :status }
        end
      end

      def kill
        Resque::Plugins::Status::Hash.kill(params[:id])
        s = Resque::Plugins::Status::Hash.get(params[:id])
        s.status = 'killed'
        Resque::Plugins::Status::Hash.set(params[:id], s)
        redirect_to statuses_resque_path
      end

      def cleaner
        load_cleaner_filter

        @jobs = @cleaner.select
        @stats, @total = {}, {"total" => 0, "1h" => 0, "3h" => 0, "1d" => 0, "3d" => 0, "7d" => 0}
        @jobs.each do |job|
          klass = job["payload"]["class"]
          failed_at = Time.parse job["failed_at"]

          @stats[klass] ||= {"total" => 0, "1h" => 0, "3h" => 0, "1d" => 0, "3d" => 0, "7d" => 0}
          items = [@stats[klass], @total]

          items.each { |a| a["total"] += 1 }
          items.each { |a| a["1h"] += 1 } if failed_at >= hours_ago(1)
          items.each { |a| a["3h"] += 1 } if failed_at >= hours_ago(3)
          items.each { |a| a["1d"] += 1 } if failed_at >= hours_ago(24)
          items.each { |a| a["3d"] += 1 } if failed_at >= hours_ago(24*3)
          items.each { |a| a["7d"] += 1 } if failed_at >= hours_ago(24*7)
        end
      end

      def cleaner_list
        load_cleaner_filter

        block = filter_block

        @failed = @cleaner.select(&block).reverse

        url = "cleaner_list?c=#{@klass}&ex=#{@exception}&f=#{@from}&t=#{@to}"
        @dump_url = "cleaner_dump?c=#{@klass}&ex=#{@exception}&f=#{@from}&t=#{@to}"
        @paginate = ResqueManager::Paginate.new(@failed, url, params[:p].to_i)

        @klasses = @cleaner.stats_by_class.keys
        @exceptions = @cleaner.stats_by_exception.keys
        @count = @cleaner.select(&block).size
      end

      def cleaner_exec
        load_cleaner_filter

        if params[:select_all_pages]!="1"
          @sha1 = {}
          params[:sha1].split(",").each { |s| @sha1[s] = true }
        end

        block = filter_block

        @count =
            case params[:form_action]
              when "clear" then
                @cleaner.clear(&block)
              when "retry_and_clear" then
                @cleaner.requeue(true, &block)
              when "retry" then
                @cleaner.requeue(false, {}, &block)
            end

        @link_url = "cleaner_list?c=#{@klass}&ex=#{@exception}&f=#{@from}&t=#{@to}"
      end

      def cleaner_dump
        load_cleaner_filter

        block = filter_block
        failures = @cleaner.select(&block)
        # pretty generate throws an error with the json gem on jruby
        output = JSON.pretty_generate(failures) rescue failures.to_json
        render :json => output
      end

      def cleaner_stale
        @cleaner.clear_stale
        redirect_to cleaner_resque_path
      end


      private

      def check_connection
        Resque.keys
      rescue Errno::ECONNREFUSED
        render(:template => 'resque_manager/resque/error', :layout => false, :locals => {:error => "Can't connect to Redis! (#{Resque.redis_id})"})
        false
      end

      def find_worker(worker)
        return nil if worker.blank?
        worker = CGI::unescape(worker)
        first_part, *rest = worker.split(':')
        first_part.gsub!(/_/, '.')
        Resque::Worker.find("#{first_part}:#{rest.join(':')}")
      end

      # resque-cleaner methods

      def get_cleaner
        @cleaner ||= Resque::Plugins::ResqueCleaner.new
        @cleaner.print_message = false
        @cleaner
      end

      def load_cleaner_filter
        @from = params[:f].blank? ? nil : params[:f]
        @to = params[:t].blank? ? nil : params[:t]
        @klass = params[:c].blank? ? nil : params[:c]
        @exception = params[:ex].blank? ? nil : params[:ex]
      end

      def filter_block
        lambda { |j|
          (!@from || j.after?(hours_ago(@from))) &&
              (!@to || j.before?(hours_ago(@to))) &&
              (!@klass || j.klass?(@klass)) &&
              (!@exception || j.exception?(@exception)) &&
              (!@sha1 || @sha1[Digest::SHA1.hexdigest(j.to_json)])
        }
      end

      def hours_ago(h)
        Time.now - h.to_i*60*60
      end
    end
  end
end