class CreateProjects < ActiveRecord::Migration
  def change
    create_table :projects do |t|
      t.text :name
      t.text :network
      t.text :image
      t.text :security_group
      t.text :domain
      t.text :floating_ips # Serialized
      t.text :availability_zone
      t.text :mcollective_username
      t.text :mcollective_password
      t.text :activemq_admin_password
      t.text :activemq_user_password
      t.text :mongodb_username
      t.text :mongodb_password
      t.text :mongodb_admin_username
      t.text :mongodb_admin_password
      t.text :openshift_username
      t.text :openshift_password
      t.text :bind_key
      t.text :valid_gear_sizes

      t.integer :lab_id
      t.timestamps
    end
  end
end
