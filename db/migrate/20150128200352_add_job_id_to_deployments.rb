class AddJobIdToDeployments < ActiveRecord::Migration
  def change
    add_column :deployments, :job_id, :integer
  end
end
