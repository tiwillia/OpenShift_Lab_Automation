class AddV3InstanceIdToDeployments < ActiveRecord::Migration
  def change
    add_column :deployments, :v3_instance_id, :integer
  end
end
