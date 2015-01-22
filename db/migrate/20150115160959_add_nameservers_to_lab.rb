class AddNameserversToLab < ActiveRecord::Migration
  def change
    add_column :labs, :nameservers, :text
  end
end
