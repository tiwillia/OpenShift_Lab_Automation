class AddInstanceIdToDeployment < ActiveRecord::Migration
  def change
    add_column :deployments, :instance_id, :integer
  end
end
