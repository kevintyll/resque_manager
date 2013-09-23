Rails.application.routes.draw do
  mount ResqueManager::Engine => 'resque'
end
