class CreateTemplates < ActiveRecord::Migration
  def change
    create_table :templates do |t|
      t.integer :project_id

      t.timestamps
    end
  end
end
