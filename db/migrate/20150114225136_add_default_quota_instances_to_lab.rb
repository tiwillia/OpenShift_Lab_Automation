class AddDefaultQuotaInstancesToLab < ActiveRecord::Migration
  def change
    add_column :labs, :default_quota_instances, :integer, :default => 15
  end
end
