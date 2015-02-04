class AddStatusToDeployments < ActiveRecord::Migration
  def change
    add_column :deployments, :status, :text
  end
end
