RailsApp::Application.routes.draw do

  resources :v2_instances
  resources :v2_projects
  resources :v3_instances
  resources :v3_projects
  resources :labs
  resources :templates

  match 'admin' => 'admin#index'

  match 'v2_projects/:id/check_out' => 'v2_projects#check_out'
  match 'v2_projects/:id/uncheck_out' => 'v2_projects#uncheck_out'
  match 'v2_projects/:id/deploy' => 'v2_projects#deploy_all'
  match 'v2_projects/:id/deploy_one' => 'v2_projects#deploy_one'
  match 'v2_projects/:id/undeploy' => 'v2_projects#undeploy_all'
  match 'v2_projects/:id/redeploy' => 'v2_projects#redeploy_all'
  match 'v2_projects/:id/destroy_on_backend' => 'v2_projects#destroy_on_backend'
  match 'v2_projects/:id/check_deployed' => 'v2_projects#check_deployed'
  match 'v2_projects/:id/dns_conf_file' => 'v2_projects#dns_conf_file', :defaults => { :format => 'text' }

  match 'v3_projects/:id/check_out' => 'v3_projects#check_out'
  match 'v3_projects/:id/uncheck_out' => 'v3_projects#uncheck_out'
  match 'v3_projects/:id/deploy' => 'v3_projects#deploy_all'
  match 'v3_projects/:id/deploy_one' => 'v3_projects#deploy_one'
  match 'v3_projects/:id/undeploy' => 'v3_projects#undeploy_all'
  match 'v3_projects/:id/redeploy' => 'v3_projects#redeploy_all'
  match 'v3_projects/:id/destroy_on_backend' => 'v3_projects#destroy_on_backend'
  match 'v3_projects/:id/check_deployed' => 'v3_projects#check_deployed'
  match 'v3_projects/:id/dns_conf_file' => 'v3_projects#dns_conf_file', :defaults => { :format => 'text' }

  match 'v2_instances/:id/undeploy' => 'v2_instances#undeploy'
  match 'v2_instances/:id/callback_script' => 'v2_instances#callback_script'
  match 'v2_instances/:id/check_deployed' => 'v2_instances#check_deployed'
  match 'v2_instances/:id/reachable' => 'v2_instances#reachable'
  match 'v2_instances/:id/install_log' => 'v2_instances#install_log'
  match 'v2_instances/:id/console' => 'v2_instances#console'

  match 'v3_instances/:id/undeploy' => 'v3_instances#undeploy'
  match 'v3_instances/:id/callback_script' => 'v3_instances#callback_script'
  match 'v3_instances/:id/check_deployed' => 'v3_instances#check_deployed'
  match 'v3_instances/:id/reachable' => 'v3_instances#reachable'
  match 'v3_instances/:id/install_log' => 'v3_instances#install_log'
  match 'v3_instances/:id/console' => 'v3_instances#console'
  match 'v3_instances/:id/ansible_hosts_file' => 'v3_instances#ansible_hosts_file'
  match 'v3_instances/:id/docker_storage_setup_file' => 'v3_instances#docker_storage_setup_file'

  match 'deployments/:id/instance_message' => 'deployments#instance_message'
  match 'deployments/:id/stop' => 'deployments#stop'
  match 'deployments/:id/status' => 'deployments#status'
  match 'deployments/:id/log_messages' => 'deployments#log_messages'
  match 'templates/:id/apply' => 'templates#apply'

  match 'users/:id/make_admin' => 'users#make_admin'
  match 'users/:id/remove_admin' => 'users#remove_admin'

  match 'help' => 'welcome#help'

  match "/delayed_job" => DelayedJobWeb, :anchor => false, via: [:get, :post]
  root :to => 'v2_projects#index'

  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
