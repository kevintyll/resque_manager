module Resque
  def self.throttle(queue, limit = 10000, sleep_for = 60)
    loop do
      break if Resque.size(queue.to_s) < limit
      sleep sleep_for
    end
  end
end