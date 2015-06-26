class Lab < ActiveRecord::Base
  # attr_accessible :title, :body

  has_many :v2_projects

  validates :name,:controller,:username,:password,:api_url,:auth_tenant, :nameservers, presence: true
  validate :can_connect

  serialize :nameservers

  def alive?
    ostack = get_compute
    ostack.authok?
  end

  def get_keystone
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => self.auth_tenant, :service_type => "identity"})
  end

  def get_compute(tenant = self.auth_tenant)
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => tenant, :service_type => "compute"})
  end

  def get_neutron(tenant = self.auth_tenant)
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => tenant, :service_type => "network"})
  end

  def get_cinder(tenant = self.auth_tenant)
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => tenant, :service_type => "volume"})
  end

private

  def can_connect
    if not alive?
      errors.add(:connection, "could not be made.")
    end
  end

end
