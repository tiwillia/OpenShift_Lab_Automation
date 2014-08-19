class AddReachableToInstances < ActiveRecord::Migration
  def change
    add_column :instances, :reachable, :boolean, :default => false
  end
end
