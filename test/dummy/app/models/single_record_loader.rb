class SingleRecordLoader
  include Resque::Plugins::ChainedStatus
  @queue = :single_record_loader

  def self.perform(*args)
    #stub
  end
end