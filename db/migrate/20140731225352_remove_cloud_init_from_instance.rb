class RemoveCloudInitFromInstance < ActiveRecord::Migration
  def change
    remove_column :instances, :cloud_init
  end
end
