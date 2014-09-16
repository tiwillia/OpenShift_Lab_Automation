class AddNoOpenshiftToInstance < ActiveRecord::Migration
  def change
    add_column :instances, :no_openshift, :boolean, :default => false
  end
end
