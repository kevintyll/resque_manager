require 'test/unit'
require File.expand_path(File.dirname(__FILE__) + '/../../test_helper')

# Testing chained status mixin through SingleRecordLoader

class ChainedStatusTest < Test::Unit::TestCase
  context 'Resque::Plugins::ChainedStatus' do
    setup { @uuid   = Resque::Plugins::Status::Hash.generate_uuid }

    context '#included' do
      should 'have Resque::Plugins::Status and InstanceOverrides included' do
        assert_includes SingleRecordLoader.included_modules, Resque::Plugins::ChainedStatus::InstanceOverrides, SingleRecordLoader.included_modules.inspect
        assert_includes SingleRecordLoader.included_modules, Resque::Plugins::Status, SingleRecordLoader.included_modules.inspect
        assert_includes SingleRecordLoader.included_modules, Resque::Plugins::ChainedStatus, SingleRecordLoader.included_modules.inspect
      end
    end

    context 'InstanceOverrides' do
      setup do
        @worker = Resque::Worker.new(:data_contribution_file)
        @single_record_loader  = SingleRecordLoader.new(@uuid, @worker)
      end

      context '#name' do
        should 'return nil for no status.name' do
          assert_nil @single_record_loader.name
        end

        should 'return the status name' do
          @single_record_loader.stubs(:status).returns(Resque::Plugins::Status::Hash.new().merge('uuid' => @uuid, 'name' => 'single_record_loader'))
          assert_equal 'single_record_loader', @single_record_loader.name, @single_record_loader.name.inspect
        end
      end

      context '#completed' do
        should 'add custom messages' do
          response = @single_record_loader.completed(message: 'test', message2: 'testing')
          assert_equal 'test',    response.last[:message], response.inspect
          assert_equal 'testing', response.last[:message2], response.inspect
        end
      end
    end

    context 'ClassOverrides' do
      context '#enqueu_to' do
        should 'raise an ArgumentError for a missing UUID' do
          assert_raises(ArgumentError) { SingleRecordLoader.enqueue_to(:data_contribution_file, 'SingleRecordLoader') }
        end

        should 'return a uuid and call Resque.enqueue_to' do
          Resque.expects(:enqueue_to).with(:data_contribution_file, 'SingleRecordLoader', @uuid, { 'uuid' => @uuid }).returns(true)
          assert_equal @uuid,  SingleRecordLoader.enqueue_to(:data_contribution_file, 'SingleRecordLoader', { 'uuid' => @uuid })
        end

        should 'return nil' do
          Resque.expects(:enqueue_to).with(:data_contribution_file, 'SingleRecordLoader', @uuid, { 'uuid' => @uuid }).returns(false)
          Resque::Plugins::Status::Hash.expects(:remove).with(@uuid)
          assert_nil SingleRecordLoader.enqueue_to(:data_contribution_file, 'SingleRecordLoader', { 'uuid' => @uuid })
        end
      end
    end
  end
end
