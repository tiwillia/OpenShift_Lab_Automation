class RenameProjectIdToV2ProjectIdForTemplates < ActiveRecord::Migration
  def up
    rename_column :templates, :project_id, :v2_project_id
  end

  def down
    rename_column :templates, :v2_project_id, :project_id
  end
end
