module ResqueManager
  class Engine < ::Rails::Engine
    isolate_namespace ResqueManager

    initializer "resque_manager.assets.precompile" do |app|
      app.config.assets.precompile += %w(resque_manager/application.css resque_manager/application.js)
    end
  end
end
