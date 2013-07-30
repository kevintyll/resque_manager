module Resque
  module Plugins
    module Status
      class Hash < ::Hash
        # The STATUSES constant is frozen, so we'll just manually add the paused? method here
        def paused?
          self['status'] === 'paused'
        end
      end
    end
  end
end