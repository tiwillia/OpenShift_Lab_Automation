RailsApp::Application.routes.draw do

  resources :instances
  resources :projects
  resources :labs
  resources :templates
  match 'projects/:id/check_out' => 'projects#check_out'
  match 'projects/:id/uncheck_out' => 'projects#uncheck_out'
  match 'projects/:id/start' => 'projects#start_all'
  match 'projects/:id/stop' => 'projects#stop_all'
  match 'projects/:id/restart' => 'projects#restart_all'
  match 'instances/:id/start' => 'instances#start'
  match 'instances/:id/stop' => 'instances#stop'
  match 'instances/:id/restart' => 'instances#restart'
  match 'instances/:id/callback_script' => 'instances#callback_script'
  match 'instances/:id/reachable' => 'instances#reachable'
  match 'deployments/:id/instance_message' => 'deployments#instance_message'
  match 'templates/:id/apply' => 'templates#apply'
  root :to => 'projects#index'

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
