class AddRootPasswordToInstances < ActiveRecord::Migration
  def change
    add_column :instances, :root_password, :text
  end
end
