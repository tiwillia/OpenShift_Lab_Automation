class AddLastCheckedReachableToInstances < ActiveRecord::Migration
  def change
    add_column :instances, :last_checked_reachable, :datetime
  end
end
