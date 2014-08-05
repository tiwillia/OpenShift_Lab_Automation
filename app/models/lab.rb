class Lab < ActiveRecord::Base
  # attr_accessible :title, :body

  has_many :projects

  validates :name,:controller,:username,:password,:api_url,:auth_tenant, presence: true

  def alive?
    ostack = get_connection
    ostack.authok?
  end

  def get_compute(tenant = self.auth_tenant)
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => tenant, :service_type => "compute"})
  end

  def get_neutron(tenant = self.auth_tenant)
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => tenant, :service_type => "network"})
  end

end
