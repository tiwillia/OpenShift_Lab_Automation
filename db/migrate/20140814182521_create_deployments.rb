class CreateDeployments < ActiveRecord::Migration
  def change
    create_table :deployments do |t|
      t.integer :project_id
      t.integer :started_by
      t.text :action
      t.boolean :complete, :default => false
      t.boolean :started, :default => false
      t.datetime :started_time
      t.datetime :completed_time

      t.timestamps
    end
  end
end
