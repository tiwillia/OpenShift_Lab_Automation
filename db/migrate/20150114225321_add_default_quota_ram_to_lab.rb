class AddDefaultQuotaRamToLab < ActiveRecord::Migration
  def change
    add_column :labs, :default_quota_ram, :integer, :default => 30720
  end
end
