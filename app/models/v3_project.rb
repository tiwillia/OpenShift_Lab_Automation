class V3Project < ActiveRecord::Base
  #attr_accessible :availabliltiy_zone, :checked_out_at, :checked_out_by, :deployed, :domain, :floating_ips, :hidden, :inactive_reminder_sent_at, :lab_id, :name, :network, :openshift_password, :openshift_username, :ose_version, :security_group, :uuid

  include Project

  has_many :v3_instances

  def ready?
  end

  def details
  end

  def apply_template
  end

  def available_floating_ips
  end

end
