class MoveImageFromProjectToInstance < ActiveRecord::Migration

  def change
    remove_column :projects, :image
    add_column :instances, :image, :string
  end

end
