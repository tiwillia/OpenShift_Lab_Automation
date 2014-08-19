class AddDeploymentDetailsToInstance < ActiveRecord::Migration
  def change
    add_column :instances, :deployment_started, :boolean, :default => false
    add_column :instances, :deployment_completed, :boolean, :default => false
  end
end
