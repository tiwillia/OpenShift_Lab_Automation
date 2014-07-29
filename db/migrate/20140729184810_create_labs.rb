class CreateLabs < ActiveRecord::Migration
  def change
    create_table :labs do |t|
      t.text :name
      t.text :controller
      t.text :geo
      t.text :username
      t.text :password
      t.text :api_url
      t.text :auth_tenant
      t.timestamps
    end
  end
end
