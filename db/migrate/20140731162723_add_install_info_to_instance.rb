class AddInstallInfoToInstance < ActiveRecord::Migration
  def change
    add_column :instances, :cloud_init, :text
    add_column :instances, :install_variables, :text
  end
end
