ResqueManager::Engine.routes.draw do

  root to: "resque#overview"

  resource 'resque', only: [:index], path: '', controller: 'resque' do
    get :overview
    get :workers
    get :working
    get :queues
    get :poll
    get :stats
    get :status_poll
    delete :remove_job
    delete :stop_worker
    put :pause_worker
    put :continue_worker
    put :restart_worker
    post :start_worker
    get :status_poll
    get :schedule
    put :schedule_requeue
    post :add_scheduled_job
    delete :remove_from_schedule
    post :start_scheduler
    delete :stop_scheduler
    delete :clear_statuses
    get :statuses
    get :status
    delete :kill
    get :cleaner
    get :cleaner_list
    post :cleaner_exec
    post :cleaner_dump
    post :cleaner_stale
  end
end
