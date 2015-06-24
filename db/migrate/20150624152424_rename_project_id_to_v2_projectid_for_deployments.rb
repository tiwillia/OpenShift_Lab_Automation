class RenameProjectIdToV2ProjectidForDeployments < ActiveRecord::Migration
  def up
    rename_column :deployments, :project_id, :v2_project_id
  end

  def down
    rename_column :deployments, :v2_project_id, :project_id
  end
end
