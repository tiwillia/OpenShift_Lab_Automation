class ChangeInstancesNameToV2Instances < ActiveRecord::Migration
  def up
    rename_table :instances, :v2_instances
  end

  def down
    rename_table :v2_instances, :instances
  end
end
