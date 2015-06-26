class ChangeDeploymentsToPolymorphicAssociation < ActiveRecord::Migration
  def change
    add_column :deployments, :deployable_id, :integer
    add_column :deployments, :deployable_type, :string
    remove_column :deployments, :v2_project_id
  end
end
