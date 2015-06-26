class CreateV3Instances < ActiveRecord::Migration
  def change
    create_table :v3_instances do |t|
      t.text :name
      t.text :types
      t.text :floating_ip
      t.text :internal_ip
      t.text :fqdn
      t.integer :v3_project_id
      t.text :root_password
      t.string :flavor
      t.string :image
      t.boolean :deployment_started, :default => false
      t.boolean :deployment_completed, :default => false
      t.boolean :reachable, :default => false
      t.datetime :last_checked_reachable
      t.integer :volume_storage_gb, :default => 5
      t.string :uuid

      t.timestamps
    end
  end
end
