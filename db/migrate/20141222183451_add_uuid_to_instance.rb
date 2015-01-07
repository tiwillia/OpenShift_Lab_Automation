class AddUuidToInstance < ActiveRecord::Migration
  def change
    add_column :instances, :uuid, :string, :default => nil
  end
end
