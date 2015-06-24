class V3Project < ActiveRecord::Base
  #attr_accessible :availabliltiy_zone, :checked_out_at, :checked_out_by, :deployed, :domain, :floating_ips, :hidden, :inactive_reminder_sent_at, :lab_id, :name, :network, :openshift_password, :openshift_username, :ose_version, :security_group, :uuid

  include Project

  has_many :v3_instances

  def instances
    self.v3_instances
  end

  def find_instance(instance_id)
    V3Instance.find(instance_id)
  end

  def ready?
  end

  def details
  end

  def apply_template
  end

end
