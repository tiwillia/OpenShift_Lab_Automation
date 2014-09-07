class AddDeployedToProject < ActiveRecord::Migration
  def change
    add_column :projects, :deployed, :boolean, :default => false
  end
end
