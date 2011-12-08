require 'resque/failure/redis'
module Resque
  module Failure
    class Redis
      def filter_backtrace(backtrace)
        index = backtrace.index { |item| item.include?('/lib/resque_ui/overrides/resque/job.rb') }
        backtrace.first(index.to_i)
      end
    end
  end
end