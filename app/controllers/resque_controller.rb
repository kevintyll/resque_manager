require 'resque'
require 'resque/version'

class ResqueController < ApplicationController
  unloadable(self) #needed to prevent errors with authenticated system in dev env.

  layout 'resque'

  before_filter :check_connection

  verify :method => :post, :only => [:clear_failures],
    :render => { :text => "<p>Please use the POST http method to post data to this API.</p>" }

  
  def index
    redirect_to(:action => 'overview')
  end

  def working
    render(:partial => 'working', :layout => 'resque')
  end

#  def workers
#    render(:partial => 'workers', :layout => 'resque')
#  end

  def queues
    render(:partial => 'queues', :layout => 'resque', :locals => {:partial => nil})
  end

  def poll
    @polling = true
    render(:text => (render_to_string(:action => params[:page],:layout => false, :resque => Resque)).gsub(/\s{1,}/, ' '))
  end

  #
  #  %w( overview workers ).each do |page|
  #    get "/#{page}.poll" do
  #      content_type "text/plain"
  #      @polling = true
  #      show(page.to_sym, false).gsub(/\s{1,}/, ' ')
  #    end
  #  end
  #
  def failed
    if Resque::Failure.url
      redirect_to Resque::Failure.url
    end
  end

  def clear_failures
    Resque::Failure.clear
    redirect_to(:action => 'failed')
  end

  def stats
    unless params[:id]
      redirect_to(:action => 'stats',:id => 'resque')
    end

    if params[:id] == 'txt'
      info = Resque.info

      stats = []
      stats << "resque.pending=#{info[:pending]}"
      stats << "resque.processed+=#{info[:processed]}"
      stats << "resque.failed+=#{info[:failed]}"
      stats << "resque.workers=#{info[:workers]}"
      stats << "resque.working=#{info[:working]}"

      Resque.queues.each do |queue|
        stats << "queues.#{queue}=#{Resque.size(queue)}"
      end
    
      render(:text => stats.join("</br>"))
    end
  end

  private

  def check_connection
    Resque.keys
  rescue Errno::ECONNREFUSED
    render(:template => 'resque/error', :layout => false, :locals => {:error => "Can't connect to Redis! (#{Resque.redis.server})"})
    false
  end
end
