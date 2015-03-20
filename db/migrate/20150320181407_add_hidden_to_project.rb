class AddHiddenToProject < ActiveRecord::Migration
  def change
    add_column :projects, :hidden, :boolean, :default => false
  end
end
