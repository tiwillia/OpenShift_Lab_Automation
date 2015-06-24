class ChangeProjectsNameToV2Projects < ActiveRecord::Migration
  def up
    rename_table :projects, :v2_projects
  end

  def down
    rename_table :v2_projects, :projects
  end
end
