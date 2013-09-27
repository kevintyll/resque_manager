module ResqueScheduler
  def schedule=(schedule_hash)
    raise 'not implemented'
  end

  # Returns the schedule hash
  def schedule
    #the scheduler gem expects a hash, but it's now stored in
    #redis as an array.
    hash = {}
    Resque.list_range(:scheduled, 0, -0).each do |job|
      hash.merge! job
    end
    hash
  end

  def self.start(ips)
    if Rails.env =~ /development|test/
      Thread.new{system('rake resque:scheduler')}
    else
      Thread.new(ips){|ip_list|system("cd #{Rails.root}; #{ResqueManager::Cap.path} #{Rails.env} resque:scheduler host=#{ip_list}")}
    end
  end

  def self.quit(ips)
    if Rails.env =~ /development|test/
      system('rake resque:quit_scheduler')
    else
      system("cd #{Rails.root}; bundle exec cap #{Rails.env} resque:quit_scheduler host=#{ips}")
    end
  end

  def self.restart(ips)
    quit(ips)
    start(ips)
  end

  def self.farm_status
    status = {}
    if Rails.env =~ /development|test/
      status['localhost'] = pids.present? ? 'Running' : 'Stopped'
    else
      Resque.schedule.values.collect{|job| job['ip']}.each do |ip|
        cap = `cd #{Rails.root}; bundle exec cap #{Rails.env} resque:scheduler_status hosts=#{ip}`
        status[ip] = cap =~ /resque:scheduler is up/ ? 'Running' : 'Stopped'
      end
    end
    status
  end

  # Returns an array of string pids of all the other workers on this
  # machine. Useful when pruning dead workers on startup.
  def self.pids
    `ps -A -o pid,command | grep [r]esque:scheduler`.split("\n").map do |line|
      line.split(' ')[0]
    end
  end
end
