class RenameProjectIdToV2ProjectIdForV2Instances < ActiveRecord::Migration
  def up
    rename_column :v2_instances, :project_id, :v2_project_id
  end

  def down
    rename_column :v2_instances, :v2_project_id, :project_id
  end
end
