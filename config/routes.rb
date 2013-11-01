ResqueManager::Engine.routes.draw do

  root to: "resque#overview"

  resource 'resque', only: [:index], path: '', controller: 'resque' do
    member do
      get :overview
      get :workers
      get :working
      get :queues
      get :poll
      get :stats
      get :status_poll
      post :remove_job
      post :stop_worker
      post :pause_worker
      post :continue_worker
      post :restart_worker
      post :start_worker
      get :status_poll
      get :schedule
      post :schedule_requeue
      post :add_scheduled_job
      post :remove_from_schedule
      post :start_scheduler
      post :stop_scheduler
      get :statuses
      post :clear_statuses
      get :statuses
      get :status
      post :kill
      get :cleaner
      get :cleaner_list
      post :cleaner_exec
      post :cleaner_dump
      post :cleaner_stale
    end
  end
end
