require File.expand_path(File.dirname(__FILE__) + '/../../test_helper')
require 'resque_manager/resque_controller.rb'

module ResqueManager
  class ResqueControllerTest < ActionController::TestCase
    context 'ResqueManager::ResqueController' do
      setup { Resque.redis.flushdb } # flush redis
      context '#working' do
        should 'respond with success and render the _working partial' do
          get :working, use_route: :resque_manager
          assert_response :success
          assert_template partial: '_working'
        end
      end

      context '#queues' do
        should 'respond with success and render the _queues partial' do
          get :queues, use_route: :resque_manager
          assert_response :success
          assert_template partial: '_queues'
        end
      end

      context '#poll' do
        should 'respond with success and start the live polling' do
          get :poll, {page: 'overview', use_route: :resque_manager}
          assert_response :success
          assert_select 'p.poll', text: /Last Updated: [0-9]{2}:[0-9]{2}:[0-9]{2}/, count: 1
        end
      end

      context '#status_poll' do
        should 'respond with success and start the live polling' do
          get :status_poll, use_route: :resque_manager
          assert_response :success
          assert_select 'p.poll', text: /Last Updated: [0-9]{2}:[0-9]{2}:[0-9]{2}/, count: 1
        end
      end

      context '#remove_job' do
        should 'always redirect' do
          @request.env['HTTP_REFERER'] = '/resque/queues/single_record_loader'
          post :remove_job, {class: SingleRecordLoader, use_route: :resque_manager}
          assert_redirected_to '/resque/queues/single_record_loader'
        end

        should 'dequeue' do
          ResqueManager.applications.expects(:blank?).returns(true)
          Resque.expects(:dequeue)
          @request.env['HTTP_REFERER'] = '/resque/queues/single_record_loader'
          post :remove_job, {class: SingleRecordLoader, use_route: :resque_manager}
          assert_redirected_to '/resque/queues/single_record_loader'
        end
      end

      context '#stop_worker' do
        should 'always redirect to workers path' do
          post :stop_worker, use_route: :resque_manager
          assert_redirected_to '/resque/workers'
        end

        should 'stop a worker and redirect' do
          worker = Resque::Worker.new(:data_contribution_file)
          worker.expects(:quit)
          ResqueManager::ResqueController.any_instance.expects(:find_worker).returns(worker)
          post :stop_worker, {worker: worker, use_route: :resque_manager}
          assert_redirected_to '/resque/workers'
        end
      end

      context '#pause_worker' do
        should 'always redirect to workers path' do
          post :pause_worker, use_route: :resque_manager
          assert_redirected_to '/resque/workers'
        end

        should 'pause a worker and redirect' do
          worker = Resque::Worker.new(:data_contribution_file)
          worker.expects(:pause)
          ResqueManager::ResqueController.any_instance.expects(:find_worker).returns(worker)
          post :pause_worker, {worker: worker, use_route: :resque_manager}
          assert_redirected_to '/resque/workers'
        end
      end

      context '#continue_worker' do
        should 'always redirect to workers path' do
          post :continue_worker, use_route: :resque_manager
          assert_redirected_to '/resque/workers'
        end

        should 'continue a worker and redirect' do
          worker = Resque::Worker.new(:data_contribution_file)
          worker.expects(:continue)
          ResqueManager::ResqueController.any_instance.expects(:find_worker).returns(worker)
          post :continue_worker, {worker: worker, use_route: :resque_manager}
          assert_redirected_to '/resque/workers'
        end
      end

      context '#restart_worker' do
        should 'always redirect to workers path' do
          post :restart_worker, use_route: :resque_manager
          assert_redirected_to '/resque/workers'
        end

        should 'continue a worker and redirect' do
          worker = Resque::Worker.new(:data_contribution_file)
          worker.expects(:restart)
          ResqueManager::ResqueController.any_instance.expects(:find_worker).returns(worker)
          post :restart_worker, {worker: worker, use_route: :resque_manager}
          assert_redirected_to '/resque/workers'
        end
      end

      context '#start_worker' do
        should 'always redirect to workers path' do
          post :start_worker, use_route: :resque_manager
          assert_redirected_to '/resque/workers'
        end

        should 'continue a worker and redirect' do
          worker = Resque::Worker.new(:data_contribution_file)
          Resque::Worker.expects(:start)
          post :start_worker, {worker: worker, use_route: :resque_manager}
          assert_redirected_to '/resque/workers'
        end
      end

      context '#stats' do
        should 'redirect to /stats/resque for a missing id' do
          post :stats, use_route: :resque_manager
          assert_redirected_to '/resque/stats?id=resque'
        end

        should 'render resque info text when id is txt' do
          post :stats, id: 'txt', use_route: :resque_manager
          assert_equal 'resque.pending=0</br>resque.processed+=0</br>resque.failed+=0</br>resque.workers=0</br>resque.working=0', @response.body, @response.body
        end
      end

      context '#schedule' do
        should 'have a response of success' do
          get :schedule, use_route: :resque_manager
          assert_response :success
        end
      end

      context '#schedule_requeue' do
        should 'always redirect to overview' do
          Resque::Scheduler.stubs(:enqueue_from_config)
          post :schedule_requeue, use_route: :resque_manager
          assert_redirected_to '/resque/overview'
        end
      end

      context '#add_scheduled_job' do
        should 'have an error for a name already existing and missing ip and missing cron' do
          # Resque.schedule.keys.expects(:include?).returns(true)
          # Stub on array instead of Resque.schedule.keys otherwise the stub never works.
          Array.any_instance.expects(:include?).returns(true).at_least_once
          post :add_scheduled_job, {name: 'key', use_route: :resque_manager}
          assert_redirected_to '/resque/schedule'
          errors = flash[:error].split('<br>')
          assert_includes errors, 'You must enter an ip address for the server you want this job to run on.', errors.inspect
          assert_includes errors, 'You must enter the cron schedule.', errors.inspect
          assert_includes errors, 'Name already exists.'
        end

        should 'add a job to the scheduler' do
          ip = '0.0.0.0'
          Resque.redis.expects(:rpush)
          ResqueScheduler.expects(:restart).with(ip)
          post :add_scheduled_job, {'name' => 'TestName', 'class' => 'SingleRecordLoader', 'ip' => ip, 'args' => nil, 'description' => 'Test job', 'cron' => 'TestCron', use_route: :resque_manager}
          assert_nil flash[:error]
        end
      end

      context '#remove_from_schedule' do
        should 'always redirect to schedule' do
          post :remove_from_schedule, use_route: :resque_manager
          assert_redirected_to '/resque/schedule'
        end

        should 'restart schedule from ip' do
          Resque.stubs(:list_range).returns([{'SingleRecordLoader' => 'test data'}])
          Resque.redis.expects(:lrem).with(:scheduled, 0, {'SingleRecordLoader' => 'test data'}.to_json)
          ResqueScheduler.expects(:restart).with('0.0.0.0')
          post :remove_from_schedule, {ip: '0.0.0.0', job_name: 'SingleRecordLoader', use_route: :resque_manager}
          assert_redirected_to '/resque/schedule'
        end
      end

      context '#start_scheduler' do
        should 'always redirect to schedule and call ResqueScheduler.start' do
          ResqueScheduler.expects(:start).with('0.0.0.0')
          post :start_scheduler, {ip: '0.0.0.0', use_route: :resque_manager}
          assert_redirected_to '/resque/schedule'
        end
      end

      context '#stop_scheduler' do
        should 'always redirect to schedule and call ResqueScheduler.start' do
          ResqueScheduler.expects(:quit).with('0.0.0.0')
          post :stop_scheduler, {ip: '0.0.0.0', use_route: :resque_manager}
          assert_redirected_to '/resque/schedule'
        end
      end

      context '#statuses' do
        should 'respond with a status in json format' do
          hash = Resque::Plugins::Status::Hash.set('UUID', 'message')
          Resque::Plugins::Status::Hash.stubs(:status_ids).returns(%w(UUID))
          get :statuses, {format: :js, use_route: :resque_manager}
          assert_equal hash, JSON.parse(@response.body).first, JSON.parse(@response.body).inspect
        end

        should 'render the page in html format' do
          hash = Resque::Plugins::Status::Hash.set('UUID', 'message')
          Resque::Plugins::Status::Hash.stubs(:status_ids).returns(%w(UUID))
          get :statuses, {use_route: :resque_manager}
          assert_select 'h1', 'Statuses'
        end
      end

      context '#clear_statuses' do
        should 'always redirect to statuses page and call Resque::Plugins::Status::Hash.clear' do
          Resque::Plugins::Status::Hash.expects(:clear)
          get :clear_statuses, use_route: :resque_manager
          assert_redirected_to '/resque/statuses'
        end
      end

      context '#status' do
        should 'render a status in json' do
          hash = Resque::Plugins::Status::Hash.set('UUID', 'message')
          get :status, {id: 'UUID', format: :js, use_route: :resque_manager}
          assert_equal hash, JSON.parse(@response.body), JSON.parse(@response.body).inspect
        end

        should 'render a status in html' do
          hash = Resque::Plugins::Status::Hash.set('UUID', 'message')
          post :status, {id: 'UUID', use_route: :resque_manager}
          assert_select 'h1', /Statuses:/
        end
      end

      context '#kill' do
        should 'redirect to statuses and kill a status' do
          Resque::Plugins::Status::Hash.set('UUID', 'message')
          post :kill, {id: 'UUID', use_route: :resque_manager}
          assert_redirected_to '/resque/statuses'
          hash = Resque::Plugins::Status::Hash.get('UUID')
          assert_equal 'killed', hash['status']
        end
      end

      context '#cleaner_stale' do
        should 'always redirect to cleaner' do
          Resque::Plugins::ResqueCleaner.any_instance.expects(:clear_stale)
          post :cleaner_stale, use_route: :resque_manager
          assert_redirected_to '/resque/cleaner'
        end
      end

      context 'private' do
        setup { @controller = ResqueController.new }
        context '#check_connection' do
          should 'return true' do
            assert @controller.send(:check_connection)
          end

          should 'rescue a Errno::ECONNRFUSED exception and render template resque/error' do
            # Check connection is a before_filter stub an exception and make a get request to working
            # We need an actual request to render the template
            Resque.expects(:keys).raises(Errno::ECONNREFUSED.new)
            get :working, use_route: :resque_manager
            assert_match /#{Resque.redis_id}/, @response.body, @response.body.inspect
            assert_template 'resque/error'
          end
        end

        context '#find_worker' do
          should 'return nil for a missing worker' do
            assert_nil @controller.send(:find_worker, '')
          end

          should 'find the correct worker' do
            worker = Resque::Worker.new(:data_contribution_file)
            Resque::Worker.expects(:exists?).returns(true)
            response = @controller.send(:find_worker, worker.to_s)
            first, *rest=worker.to_s.split(':')
            first.gsub!(/_/, '.')
            worker_id = "#{first}:#{rest.join(':')}"
            worker.to_s = worker_id
            assert_equal worker, response
          end
        end

        context '#get_cleaner' do
          should 'return a cleaner' do
            cleaner = @controller.send(:get_cleaner)
            assert_kind_of Resque::Plugins::ResqueCleaner, cleaner
            refute cleaner.print_message
          end
        end

        context '#hours_ago' do
          should 'return the correctly formatted hours ago time' do
            now = Time.now
            Time.expects(:now).returns(now).at_least_once
            hours = @controller.send(:hours_ago, 2)
            assert_equal now - 2*60*60, hours
          end
        end
      end
    end
  end
end
