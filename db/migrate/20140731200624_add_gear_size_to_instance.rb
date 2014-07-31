class AddGearSizeToInstance < ActiveRecord::Migration
  def change
    add_column :instances, :gear_size, :string
  end
end
