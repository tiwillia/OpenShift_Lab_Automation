class AddFlavorToInstance < ActiveRecord::Migration
  def change
    add_column :instances, :flavor, :string
  end
end
