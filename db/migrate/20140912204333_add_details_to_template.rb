class AddDetailsToTemplate < ActiveRecord::Migration
  def change
    add_column :templates, :name, :string
    add_column :templates, :description, :text
    add_column :templates, :file_location, :string
    add_column :templates, :content, :text
  end
end
