class CreateV3Projects < ActiveRecord::Migration
  def change
    create_table :v3_projects do |t|
      t.text :name
      t.text :network
      t.text :security_group
      t.text :domain
      t.text :floating_ips
      t.text :availabliltiy_zone
      t.text :openshift_username
      t.text :openshift_password
      t.integer :lab_id
      t.string :ose_version
      t.integer :checked_out_by
      t.datetime :checked_out_at
      t.boolean :deployed
      t.string :uuid
      t.date :inactive_reminder_sent_at
      t.boolean :hidden

      t.timestamps
    end
  end
end
