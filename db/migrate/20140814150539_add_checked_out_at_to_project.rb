class AddCheckedOutAtToProject < ActiveRecord::Migration
  def change
    add_column :projects, :checked_out_at, :datetime
  end
end
