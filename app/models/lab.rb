class Lab < ActiveRecord::Base
  # attr_accessible :title, :body

  has_many :projects

  def alive?
    ostack = get_connection
    ostack.authok?
  end

  def get_connection(tenant = self.auth_tenant)
    OpenStack::Connection.create({:username => self.username, :api_key => self.password, :auth_url => self.api_url, :authtenant_name => tenant, :service_type => "compute"})
  end

end
