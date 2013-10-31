require 'test/unit'
require File.expand_path(File.dirname(__FILE__) + '/../../../test_helper')

class DummyClass
  include ResqueScheduler
end

class ResqueSchedulerTest < Test::Unit::TestCase
  context 'ResqueSchedule' do
    setup { @dummy = DummyClass.new }

    context '#schedule=' do
      should 'always raise a RunTimeError' do
        err = assert_raise(RuntimeError) { @dummy.schedule = {} }
        assert_match /not implemented/, err.message
      end
    end

    context '#schedule' do
      should 'return a hash' do
        hash = { make_tea: { every: '1m' }, about: { name: 'green' } }
        Resque.stubs(:list_range).returns([hash])
        hash_response = @dummy.schedule
        assert_equal hash[:make_tea],  hash_response[:make_tea]
        assert_equal hash[:about],     hash_response[:about]
      end
    end

    context '.start' do
      should 'run rake task resque:scheduler when Rails.env is test' do
        Thread.expects(:new)
        ResqueScheduler.start('0.0.0.0')
      end

      should 'run rake task resque:scheduler when Rails.env is anything other than test or development' do
        Rails.expects(:env).returns('prod')
        Thread.expects(:new).with('0.0.0.0')
        ResqueScheduler.start('0.0.0.0')
      end
    end

    context '.quit' do
      should 'run the rake task resque:quit scheduler when Rails.env is anything other than test or development' do
        ResqueScheduler.expects(:system).with('rake resque:quit_scheduler')
        ResqueScheduler.quit('0.0.0.0')
      end

      should 'run the rake task resque:quit scheduler when Rails.env is test' do
        Rails.expects(:env).returns('prod').at_least_once
        ResqueScheduler.expects(:system).with("cd #{Rails.root}; bundle exec cap #{Rails.env} resque:quit_scheduler host=0.0.0.0")
        ResqueScheduler.quit('0.0.0.0')
      end
    end

    context '.restart' do
      should 'run quit then start' do
        ip = '0.0.0.0'
        ResqueScheduler.expects(:quit).with(ip)
        ResqueScheduler.expects(:start).with(ip)
        ResqueScheduler.restart(ip)
      end
    end

    context '.farm_status' do
      should 'set the local host status to Stopped' do
        status = ResqueScheduler.farm_status
        assert_equal 'Stopped', status['localhost']
      end

      should 'set the local host status to running' do
        ResqueScheduler.stubs(:pids).returns('pid')
        status = ResqueScheduler.farm_status
        assert_equal 'Running', status['localhost']
      end
      
      should 'set the status to stopped for ip 0.0.0.0 when cap ' do
        ResqueScheduler.expects(:`).returns('')
        Rails.expects(:env).returns('prod').at_least_once
        Resque.expects(:schedule).returns({ job: { 'ip' => '0.0.0.0' } }).at_least_once
        status = ResqueScheduler.farm_status
        assert_equal 'Stopped', status['0.0.0.0']
      end

      should 'set the status to running for ip 0.0.0.0' do
        ResqueScheduler.expects(:`).returns('resque:scheduler is up')
        Rails.expects(:env).returns('prod').at_least_once
        Resque.expects(:schedule).returns({ job: { 'ip' => '0.0.0.0' } }).at_least_once
        status = ResqueScheduler.farm_status
        assert_equal 'Running', status['0.0.0.0']
      end
    end

    context '.pids' do
      should 'return an array of pids' do
        pids = <<-eos
          123
          1234
        eos
        ResqueScheduler.expects(:`).returns(pids)
        assert_equal %w(123 1234), ResqueScheduler.pids
      end
    end
  end
end