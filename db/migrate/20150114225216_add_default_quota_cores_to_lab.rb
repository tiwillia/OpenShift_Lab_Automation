class AddDefaultQuotaCoresToLab < ActiveRecord::Migration
  def change
    add_column :labs, :default_quota_cores, :integer, :default => 45
  end
end
