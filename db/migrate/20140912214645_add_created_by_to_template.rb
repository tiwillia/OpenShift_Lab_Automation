class AddCreatedByToTemplate < ActiveRecord::Migration
  def change
    add_column :templates, :created_by, :integer
  end
end
