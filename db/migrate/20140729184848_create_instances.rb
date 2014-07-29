class CreateInstances < ActiveRecord::Migration
  def change
    create_table :instances do |t|
      t.text :name
      t.text :types # Serialized
      t.text :floating_ip
      t.text :internal_ip
      t.text :fqdn

      t.integer :project_id
      t.timestamps
    end
  end
end
