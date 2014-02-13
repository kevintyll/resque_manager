require 'test/unit'
require 'socket'
require File.expand_path(File.dirname(__FILE__) + '/../../../test_helper')

class WorkerTest < Test::Unit::TestCase
  context 'Worker' do
    setup do
      Resque.redis.flushdb # flush redis
      Thread.current[:queues] = '*'
      Thread.current[:path] = 'path'
      @worker = Resque::Worker.new(:data_contribution_file)
    end

    context '#local_ip' do
      should 'set the local_ip' do
        assert_equal UDPSocket.open { |s| s.connect('google.com', 1); s.addr.last }, @worker.local_ip
      end
    end

    context '#to_s' do
      should 'return the correct string representation of the worker'do
        Process.stubs(:pid).returns(27415)
        object_id = Thread.current.object_id
        assert_equal "#{Socket.gethostname}(#{UDPSocket.open { |s| s.connect('google.com', 1); s.addr.last }}):27415:#{object_id}:path:*", @worker.to_s
      end

      should 'alias to_s as id' do
        assert_not_nil @worker.id
      end
    end

    context '#pause' do
      should 'return a correctly formatted pause key' do
        Process.stubs(:pid).returns(27415)
        assert_equal "worker:#{Socket.gethostname}(#{UDPSocket.open { |s| s.connect('google.com', 1); s.addr.last }}):27415:all_workers:paused", @worker.pause_key
      end
    end

    context '#pid' do
      should 'return the correct pid' do
        Process.stubs(:pid).returns(27415)
        assert_equal '27415', @worker.pid
      end
    end

    context '#thread' do
      should 'return the correct thread' do
        assert_equal Thread.current.object_id.to_s, @worker.thread
      end
    end

    context '#path' do
      should 'return the correct path' do
        assert_equal Thread.current[:path], @worker.path
      end
    end

    context '#queue' do
      should 'return the correct queue' do
        assert_equal Thread.current[:queues], @worker.queue
      end
    end

    context '#workers_in_pid' do
      should 'return the worker in the redis' do
        Resque.redis.sadd(:workers, @worker.to_s)
        assert_equal @worker.to_s, @worker.workers_in_pid.first.to_s
      end

      should 'return an empty array' do
        assert_empty @worker.workers_in_pid
      end
    end

    context '#ip' do
      should 'return the correct ip' do
        assert_equal UDPSocket.open { |s| s.connect('google.com', 1); s.addr.last }, @worker.ip
      end
    end

    context '#queues_in_pid' do
      should 'return the correct queue' do
        Resque.redis.sadd(:workers, @worker.to_s)
        assert_equal '*', @worker.queues_in_pid.first
      end
    end

    context '#queues' do
      should 'return an array of queues when the queue is not *' do
        Thread.current[:queues] = 'data_contribution,single_record_loader'
        assert_equal %w(data_contribution single_record_loader), @worker.queues
      end

      should 'return an array of sorted resque queues' do
        Resque.redis.sadd(:queues, @worker.to_s)
        assert_equal @worker.to_s, @worker.queues.first
      end
    end

    context '#shutdown' do
      should 'set @shutdown to true and threads shutdown to true' do
        @worker.expects(:log).with('Exiting...')
        @worker.shutdown
        Thread.list.each { |t| assert t[:shutdown] }
        assert @worker.shutdown?
      end
    end

    context '#paused' do
      should 'return the correct pause_key' do
        now = Time.now.to_s
        Resque.redis.set(@worker.pause_key, Time.now.to_s)
        assert_equal now, @worker.paused
      end
    end

    context '#paused?' do
      should 'return true when paused is present and @paused is false' do
        now = Time.now.to_s
        Resque.redis.set(@worker.pause_key, now)
        @worker.instance_variable_set(:@paused, false)
        assert @worker.paused?
      end

      should 'return true when @paused is true' do
        @worker.instance_variable_set(:@paused, true)
        assert @worker.paused?
      end
    end

    context '#pause_processing' do
      should 'set the worker pause key to Time.now and log the pausing process' do
        @worker.expects(:log).with('USR2 received; pausing job processing')
        now = Time.now
        Time.expects(:now).returns(now).at_least_once
        @worker.pause_processing
        assert_equal now.to_s, @worker.paused
      end
    end

    context '#unpause_processing' do
      should 'delete the worker pause key and log the un-pausing process' do
        Resque.redis.set(@worker.pause_key, Time.now.to_s) # Set the pause key
        @worker.expects(:log).with('CONT received; resuming job processing')
        @worker.unpause_processing
        assert_nil @worker.paused
        refute @worker.paused?
      end
    end

    context '#prune_dead_workers' do
      should 'unregister a worker when its pid is not included in worker_pids' do
        Resque.redis.sadd(:workers, @worker.to_s)
        @worker.expects(:worker_pids).returns([])
        @worker.expects(:log!).with("Pruning dead worker: #{@worker.to_s}")
        Resque::Worker.any_instance.expects(:unregister_worker)
        @worker.prune_dead_workers
      end
    end

    context '#unregister_worker_with_pause' do
      should 'delete the pause key from redis' do
        Resque.redis.set(@worker.pause_key, Time.now.to_s)
        Redis.any_instance.expects(:del).at_least_once
        @worker.unregister_worker_with_pause
      end
    end
  end
end