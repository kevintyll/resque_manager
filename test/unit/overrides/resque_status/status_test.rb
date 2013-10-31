require 'test/unit'
require File.expand_path(File.dirname(__FILE__) + '/../../../test_helper')
# Testing resque status mixin through DataContributionFile

class StatusTest < Test::Unit::TestCase
  context 'Resque::Plugins::Status' do
    setup do
      Resque.redis.flushdb # flush redis
      @uuid   = Resque::Plugins::Status::Hash.generate_uuid
      @worker = Resque::Worker.new(:data_contribution_file)
    end

    context 'base include' do
      should 'have the attr_reader :workers' do
        data_contribution_file = DataContributionFile.new(@uuid)
        assert_includes data_contribution_file.instance_variable_names, '@worker', data_contribution_file.instance_variable_names.inspect
      end
    end
    
    context '#initialize' do
      should 'set the instance variables @uuid, @options, @worker' do
        options = { options: 'option' }
        data_contribution_file = DataContributionFile.new(@uuid, @worker, options)

        assert_equal options,  data_contribution_file.options
        assert_equal @uuid,    data_contribution_file.uuid
        assert_equal @worker,  data_contribution_file.worker
      end
    end
    
    context '.enqueue_to' do
      should 'return a uuid' do
        assert_not_nil DataContributionFile.enqueue_to(:data_contribution_file, 'SingleRecordLoader')
      end

      should 'return nil' do
        Resque.expects(:enqueue_to).returns(false)
        assert_nil DataContributionFile.enqueue_to(:data_contribution_file, 'SingleRecordLoader')
      end
    end

    context '.perform' do
      should 'return an instance of DataContributionFile with a UUID' do
        response = DataContributionFile.perform
        assert_kind_of DataContributionFile, response
        assert response.uuid.present?
      end

      should 'set options, worker and UUID' do
        options  = { options: 'Option' }
        response = DataContributionFile.perform(@uuid, options) do
          :single_record_loader
        end
        assert_equal @uuid,                 response.uuid
        assert_equal options,               response.options
        assert_equal :single_record_loader, response.worker
      end
    end

    context '.counter_key' do
      should 'return a formatted counter key' do
        assert_equal "data_contribution:#{@uuid}", DataContributionFile.counter_key('data_contribution', @uuid)
      end
    end

    context '.remove' do
      should 'remove from redis' do
        assert_equal 1, DataContributionFile.incr_counter('data_contribution', @uuid)
        DataContributionFile.remove(@uuid)
        assert_equal 0, DataContributionFile.counter('data_contribution', @uuid)
      end
    end

    context '.counter' do
      should 'return a count of 0' do
        assert_equal 0, DataContributionFile.counter('data_contribution', @uuid)
      end

      should 'return a count of 1' do
        DataContributionFile.incr_counter('data_contribution', @uuid)
        assert_equal 1, DataContributionFile.counter('data_contribution', @uuid)
      end
    end

    context '.incr_counter' do
      should 'increment the counter to one' do
        assert_equal 1, DataContributionFile.incr_counter('data_contribution', @uuid)
      end
    end

    context '#tick' do
      setup do
        @data_contribution = DataContributionFile.new(@uuid, @worker)
        @data_contribution.send(:set_status) # Set the status
      end

      should 'raise Killed when should_kill? is true' do
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(true)
        assert_raises(Resque::Plugins::Status::Killed) { @data_contribution.tick }
        end

      should 'raise Killed when status.killed? is true' do
        # Stub on the hash not the actual status because it will change and wont be stubbed on the right status object
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(false)
        Resque::Plugins::Status::Hash.any_instance.expects(:killed?).returns(true)
        assert_raises(Resque::Plugins::Status::Killed) { @data_contribution.tick }
      end

      should 'set status to working' do
        @data_contribution.status.stubs(:completed?).returns(true)
        @data_contribution.worker.expects(:paused?).returns(false).at_least_once # break so we dont hit the sleep for 60 seconds
        @data_contribution.tick
        assert_equal 'working', @data_contribution.status['status'], @data_contribution.status.inspect
      end
    end

    context '#safe_perform!' do
      setup do
        @data_contribution = DataContributionFile.new(@uuid, @worker)
        @status = Resque::Plugins::Status::Hash.new().merge('uuid' => @uuid)
        @data_contribution.stubs(:status).returns(@status)
        @now = Time.now
        Time.stubs(:now).returns(@now)
      end

      should 'rescue Killed' do
        # Stub on the hash not the actual status because it will change and wont be stubbed on the right status object
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(true)
        Rails.logger.expects(:info).with("Job #{@data_contribution} Killed at #{@now}")
        Resque::Plugins::Status::Hash.expects(:killed).with(@uuid)
        assert_nothing_raised(Resque::Plugins::Status::Killed) { @data_contribution.safe_perform! }
      end

      should 'rescue an exception and call on failure' do
        e = Exception.new('exception')
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(true)
        @data_contribution.stubs(:kill!).raises(e)
        Rails.logger.expects(:error).with(e)
        @data_contribution.expects(:on_failure).with(e)
        assert_nothing_raised(Exception) { @data_contribution.safe_perform! }
      end

      should 'rescue an exception and re-raise when the object does not respond to on failure' do
        e = Exception.new('exception')
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(true)
        @data_contribution.stubs(:kill!).raises(e)
        Rails.logger.expects(:error).with(e)
        @data_contribution.expects(:respond_to?).returns(false)
        assert_raises(Exception) { @data_contribution.safe_perform! }
      end

      should 'set the status to working then completed when !status.completed?' do
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(false)
        @status.expects(:failed?).returns(false)
        @status.expects(:completed?).returns(false)
        @data_contribution.expects(:set_status).with({'status' => 'working'})
        @data_contribution.expects(:set_status).with({'status' => 'completed', 'message' => "Completed at #{@now}" })
        @data_contribution.safe_perform!
      end

      should 'call on_failure when status.failed?' do
        @status.expects(:failed?).returns(true)
        @data_contribution.expects(:on_failure).with(@status.message)
        @data_contribution.safe_perform!
      end

      should 'call on_success' do
        Resque::Plugins::Status::Hash.expects(:should_kill?).returns(false)
        @status.expects(:failed?).returns(false)
        @status.expects(:completed?).returns(false)
        @data_contribution.expects(:on_success)
        @data_contribution.safe_perform!
      end
    end

    context '#pause!' do
      should 'set the status to paused' do
        data_contribution = DataContributionFile.new(@uuid, @worker)
        data_contribution.pause!
        assert_equal 'paused', data_contribution.status['status'], data_contribution.status.inspect
        assert_match "#{@worker} paused at", data_contribution.status['message'], data_contribution.status.inspect
      end
    end

    context '#overview_message=' do
      should 'set the overview_message for the worker' do
        @data_contribution = DataContributionFile.new(@uuid, @worker)
        @data_contribution.overview_message = 'Test'
        assert_equal 'Test', @worker.overview_message, @worker.inspect
      end
    end
  end
end