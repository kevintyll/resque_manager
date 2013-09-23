class DataContributionFile
  include Resque::Plugins::Status
  @queue = :data_contribution

  def perform
    #stub
  end

  def on_failure(e)
    #stub
  end

  def on_success
    #stub
  end

  def completed?
    #stub
  end

  def failed?
    #stub
  end

  def killed?
    #stub
  end
end