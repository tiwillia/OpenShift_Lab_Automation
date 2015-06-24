class RenameInstanceIdToV2InstanceidForDeployments < ActiveRecord::Migration
  def up
    rename_column :deployments, :instance_id, :v2_instance_id
  end

  def down
    rename_column :deployments, :v2_instance_id, :instance_id
  end
end
