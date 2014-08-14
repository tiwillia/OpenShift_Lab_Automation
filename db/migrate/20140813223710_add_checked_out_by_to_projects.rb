class AddCheckedOutByToProjects < ActiveRecord::Migration
  def change
    add_column :projects, :checked_out_by, :integer
  end
end
