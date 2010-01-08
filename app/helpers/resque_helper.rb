module ResqueHelper
  include Rack::Utils
  alias_method :h, :escape_html

  def current_section
    request.path_info.sub('/','').split('/')[1].downcase
  end

  def current_page
    url request.path_info.sub('/','').downcase
  end

  def url(*path_parts)
    [ path_prefix, path_parts ].join("/").squeeze('/')
  end
  alias_method :u, :url

  def path_prefix
    request.env['SCRIPT_NAME']
  end

  def class_if_current(page = '')
    'class="current"' if current_page.include? page.to_s
  end

  def tab(name)
    dname = "resque/#{name.to_s.downcase}"
    "<li #{class_if_current(dname)}>#{link_to(name, url(dname))}</li>"
  end

  def find_worker(worker)
    first_part, *rest = worker.split(':')
    first_part.gsub!(/_/,'.')
    Resque::Worker.find("#{first_part}:#{rest.join(':')}")
  end

  def worker_status(pid)
    s = `ps -a | grep #{pid}`
    forked_pid = s.split('resque: Forked ').last.split(' at ').first
    s = `ps -a | grep #{forked_pid}`
    s.split('resque:').last
  end
  
  def redis_get_size(key)
    case Resque.redis.type(key)
    when 'none'
      []
    when 'list'
      Resque.redis.llen(key)
    when 'set'
      Resque.redis.scard(key)
    when 'string'
      Resque.redis.get(key).length
    end
  end

  def redis_get_value_as_array(key)
    case Resque.redis.type(key)
    when 'none'
      []
    when 'list'
      Resque.redis.lrange(key, 0, 20)
    when 'set'
      Resque.redis.smembers(key)
    when 'string'
      [Resque.redis.get(key)]
    end
  end

  def show_args(args)
    Array(args).map { |a| a.inspect }.join("\n")
  end

  def partial?
    @partial
  end

  #  def partial(template, local_vars = {})
  #    @partial = true
  #    erb(template.to_sym, {:layout => false}, local_vars)
  #  ensure
  #    @partial = false
  #  end

  def poll
    if @polling
      text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
    else
      text = link_to('Live Poll', {:action => 'poll', :page => current_section}, :rel => 'poll')
    end
    "<p class='poll'>#{text}</p>"
  end

  def resque
    Resque
  end
end
