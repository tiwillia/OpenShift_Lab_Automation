class AddOpenShiftConfigurationToProject < ActiveRecord::Migration

  def change
    add_column :projects, :ose_version, :string
  end

end
