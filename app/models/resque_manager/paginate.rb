module ResqueManager
  # Paginate class used by resque-cleaner

  #Pagination helper for list page.
  class Paginate
    attr_accessor :page_size, :page, :jobs, :url

    def initialize(jobs, url, page=1, page_size=20)
      @jobs = jobs
      @url = url
      @page = (!page || page < 1) ? 1 : page
      @page_size = 20
    end

    def first_index
      @page_size * (@page-1)
    end

    def last_index
      last = first_index + @page_size - 1
      last > @jobs.size-1 ? @jobs.size-1 : last
    end

    def paginated_jobs
      @jobs[first_index, @page_size]
    end

    def first_page?
      @page <= 1
    end

    def last_page?
      @page >= max_page
    end

    def page_url(page)
      u = @url
      u += @url.include?("?") ? "&" : "?"
      if page.is_a?(Symbol)
        page = @page - 1 if page==:prev
        page = @page + 1 if page==:next
      end
      u += "p=#{page}"
    end

    def total_size
      @jobs.size
    end

    def max_page
      ((total_size-1) / @page_size) + 1
    end
  end
end
