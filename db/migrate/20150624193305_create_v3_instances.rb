class CreateV3Instances < ActiveRecord::Migration
  def change
    create_table :v3_instances do |t|
      t.text :name
      t.text :floating_ip
      t.text :internal_ip
      t.text :fqdn
      t.integer :v3_project_id
      t.text :root_password
      t.string :flavor
      t.string :image
      t.boolean :deployment_started
      t.boolean :deployment_completed
      t.boolean :reachable
      t.datetime :last_checked_reachable
      t.string :uuid

      t.timestamps
    end
  end
end
