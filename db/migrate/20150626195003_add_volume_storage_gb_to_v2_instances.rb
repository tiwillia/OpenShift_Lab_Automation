class AddVolumeStorageGbToV2Instances < ActiveRecord::Migration
  def change
    add_column :v2_instances, :volume_storage_gb, :integer, :default => 0
  end
end
