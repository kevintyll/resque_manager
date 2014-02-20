ResqueManager::Engine.routes.draw do

  root to: "resque#overview"

  resource 'resque', only: [:index], path: '', controller: 'resque' do
    #member do
      get :overview
      get :workers
      get :working
      get :queues
      get :poll
      get :stats
      get :status_poll
      delete :remove_job, path: 'remove_job/:class/:ags', as: :remove_job
      delete :stop_worker, path: 'stop_worker/:worker', as: :stop_worker
      put :pause_worker, path: 'pause_worker/:worker', as: :pause_worker
      put :continue_worker, path: 'continue_worker/:worker', as: :continue_worker
      put :restart_worker, path: 'restart_worker/:worker', as: :restart_worker
      post :start_worker
      get :status_poll
      get :schedule
      put :schedule_requeue, path: 'schedule_requeue/:job_name', as: :schedule_requeue
      post :add_scheduled_job
      delete :remove_from_schedule, path: 'remove_from_schedule/:job_name/:ip', as: :remove_from_schedule
      post :start_scheduler, path: 'start_scheduler/:ip', as: :start_scheduler
      delete :stop_scheduler, path: 'stop_scheduler/:ip', as: :stop_scheduler
      delete :clear_statuses
      get :statuses
      get :status, path: 'status/:uuid', as: :status
      delete :kill, path: 'kill/:uuid', as: :kill
      get :cleaner
      get :cleaner_list
      post :cleaner_exec
      post :cleaner_dump
      post :cleaner_stale
    end
  #end
end
