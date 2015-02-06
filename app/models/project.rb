class Project < ActiveRecord::Base
  # attr_accessible :title, :body
 
  require 'base64'
 
  belongs_to :lab
  has_many :instances
  has_many :deployments

  validates :name,:domain,:lab,:ose_version, presence: true

  before_create :create_on_backend
  before_destroy :destroy_backend
  before_destroy :destroy_instances
  before_destroy :destroy_deployments

  def deploy_all(user_id)
    deployment = self.deployments.new(:action => "build", :complete => false, :started_by => user_id)
    if deployment.save
      deployment.begin
      return true
    else
      return false
    end
  end
 
  def deploy_one(instance_id, user_id)
    deployment = self.deployments.new(:action => "single_deployment", :instance_id => instance_id, :complete => false, :started_by => user_id)
    if deployment.save
      Instance.find(instance_id).update_attributes(:deployment_started => true, :deployment_completed => false)
      deployment.begin
      return true
    else
      return false
    end
  end

  def undeploy_all(user_id)
    deployment = self.deployments.new(:action => "tear_down", :complete => false, :started_by => user_id)
    if deployment.save
      deployment.begin
      return true
    else
      return false
    end
  end

  # This will remove all instances in a project, whether they were created by
  #   the project or not.
  def destroy_all
    c = self.get_connection
    c.servers.each do |s|
      server = c.get_server(s[:id])
      if !server.delete!
        Rails.logger.error "Unable to delete server on backend: #{server.inspect}"
        return false
      end
    end
    self.instances.each do |i|
      if not i.update_attributes(:deployment_completed => false, :deployment_started => false, :reachable => false)
        Rails.logger.error "Unable to update instance after destroying on backend: #{i.inspect}"
        return false
      end
    end
    return true
  end

  def redeploy_all
    deployment = self.deployments.new(:action => "redeploy")
    if deployment.save
      deployment.begin
      return true
    else
      return false
    end
  end

  def deployment_in_progress?
    latest_deployment = self.deployments.last
    if latest_deployment.started && latest_deployment.complete == false
      true
    else
      false
    end
  end

  # This checks all instances and returns a hash in the format:
  #   {instance_id => ["deployed"|"in_progress"|"undeployed"]}
  def check_all_deployed
    c = self.get_connection
    servers = c.servers.map {|s| s[:id]}
    deployment_hash = Hash.new
    self.instances.each do |i|
      if servers.include?(i.uuid) 
        if i.deployment_completed && !i.deployment_started
          deployment_hash[i.id] = "deployed"
        else
          deployment_hash[i.id] = "in_progress"
        end
      else
        deployment_hash[i.id] = "undeployed"
      end
    end
    deployment_hash
  end

  def all_deployed?
    all_deployed = true
    self.instances.each do |i|
      next if i.deployment_completed && !i.deployment_started
      all_deployed = false
      break
    end
    all_deployed
  end

  def none_deployed?
    none_deployed = true
    self.instances.each do |i|
      next if !i.deployment_completed && !i.deployment_started
      none_deployed = false
      break
    end
    none_deployed 
  end

  def check_out(user_id)
    if User.where(:id => user_id) 
      if self.update_attributes(:checked_out_by => user_id, :checked_out_at => DateTime.now)
        return true
      else
        Rails.logger.error("Could not check out project #{self.id}")
        return false
      end
    else
      Rails.logger.error("Non-existing user checked out project #{self.id}")
    end
  end

  def uncheck_out
    if self.update_attributes(:checked_out_by => nil, :checked_out_at => nil)
      return true
    else
      Rails.logger.error("Could not check out project #{self.id}")
      return false
    end
  end

  def checked_out?
    !!self.checked_out_by
  end

  def user_can_edit?(user)
    if user && (user.admin? || self.checked_out_by == user.id)
      return true
    else
      return false
    end
  end

  def apply_template(content, assign_floating_ips=true)
    begin
      raise "Could not destroy all backend instances" unless self.destroy_all
      self.instances.each {|i| i.delete}
      self.update_attributes(content[:project_details])
      floating_ip_list = self.floating_ips if assign_floating_ips
      content["instances"].each do |i|
        new_inst = self.instances.build(i)
        new_inst.project_id = self.id
        new_inst.floating_ip = floating_ip_list.pop 
        new_inst.save
      end
    rescue => e
      Rails.logger.error "Failed to apply template to project #{self.name} with id #{self.id}."
      Rails.logger.error e.message
      Rails.logger.error e.backtrace
      return false
    end
    true
  end
 
  def details
    return nil if not self.ready?
    
    datastore_replicants = Array.new
    activemq_replicants = Array.new    
    named_entries = Array.new
    named_ip = ""
    named_hostname = ""
    broker_hostname = ""
    node_hostname = ""
  
    self.instances.each do |inst|

      if inst.types.include?("named")
        named_instance = inst
        named_ip = named_instance.floating_ip
        named_hostname = named_instance.fqdn
      end
      if inst.types.include?("datastore")
        datastore_replicants << inst.fqdn
      end
      if inst.types.include?("activemq")
        activemq_replicants << inst.fqdn
      end
      if inst.types.include?("broker")
        broker_hostname = inst.fqdn
      end      
      if inst.types.include?("node")
        node_hostname = inst.fqdn
      end

      named_entry = inst.name + ":" + inst.floating_ip
      named_entries << named_entry
    end

    return {:named_ip => named_ip, 
            :named_hostname => named_hostname,
            :broker_hostname => broker_hostname,
            :node_hostname => node_hostname, 
            :named_entries => named_entries, 
            :valid_gear_sizes => valid_gear_sizes, 
            :domain => self.domain, 
            :activemq_replicants => activemq_replicants, 
            :datastore_replicants => datastore_replicants, 
            :bind_key => self.bind_key, 
            :openshift_username => self.openshift_username, 
            :openshift_password => self.openshift_password,
            :mcollective_username => self.mcollective_username,
            :mcollective_password => self.mcollective_password,
            :activemq_admin_password => self.activemq_admin_password,
            :activemq_user_password => self.activemq_user_password,
            :mongodb_username => self.mongodb_username,
            :mongodb_password => self.mongodb_password,
            :mongodb_admin_username => self.mongodb_admin_username,
            :mongodb_admin_password => self.mongodb_admin_password,
           }
  end

  def available_floating_ips
    self.floating_ips - self.instances.map {|i| i.floating_ip }
  end

  def valid_gear_sizes
    gear_sizes = []
    self.instances.each do |i|
      if i.types.include? "node"
        gear_sizes << i.gear_size
      end
    end
    gear_sizes.uniq
  end

  # This method will ensure the project has all necessary components
  def ready?
    q = get_connection("network")
    
    network = q.networks.select {|n| n.name == self.network}
    if network.empty?
      return false, "Network #{self.network} does not exist on the tenant."
    end

    types = Array.new
    self.instances.each do |inst|
      types << inst.types
    end
    types.flatten!
    duplicates = types.select{|t| types.count(t) > 1}
    if duplicates.include?("named")
      return false, "Named is a component on multiple instances"  # If named is included more than once
    end
    if duplicates.include?("datastore") && duplicates.count("datastore") < 3
      return false, "There are 2 mongodb hosts, there must be either one or more than two."
    end
    if self.valid_gear_sizes == []
      return false, "No gear sizes are defined"
    end
    limits = self.limits
    if limits[:max_instances] < self.instances.count
      return false, "There are more #{self.instances.count - limits[:max_instances]} more instances than the project limit of \"#{limits[:max_instances]}\" allows."
    end
    types.uniq!
    types.compact!
    if types.sort == ["named", "broker", "datastore", "activemq", "node"].sort
      true
    else
      return false, "All necessary components are not included: " + types.join(",")
    end
  end

  def flavors
    c = get_connection
    flav_a = Array.new
    c.flavors.each {|f| flav_a << f[:name] }
    flav_a
  end

  def images
    c = get_connection
    image_a = Array.new
    c.images.each {|i| image_a << i[:name]}
    image_a
  end

  def floating_ips
    c = get_connection
    ip_a = Array.new
    c.floating_ips.each {|i| ip_a << i.ip}
    ip_a
  end

  # Returns a hash with the following keys:
  # :max_isntances
  # :max_cpus
  # :max_ram
  # :used_instances
  # :used_cpus
  # :used_ram
  def limits
    c = get_connection
    result = c.limits[:absolute]
    {:max_instances => result[:maxTotalInstances],
     :max_cpus => result[:maxTotalCores],
     :max_ram => result[:maxTotalRAMSize],
     :used_instances => result[:totalInstancesUsed],
     :used_cpus => result[:totalCoresUsed],
     :used_ram => result[:totalRAMUsed]}
  end

  def usage
    c = get_connection
    result = c.limits[:absolute]
  end

  def get_connection(type = "compute")
    case type
    when "compute"
      Lab.find(self.lab_id).get_compute(self.name)
    when "identity"
      Lab.find(self.lab_id).get_keystone
    when "network"
      Lab.find(self.lab_id).get_neutron(self.name)
    end 
  end

  private
    
  # Create the tenant and configure it properly on the OpenStack backend
  # TODO: Ensure backend is deleted if this fails anywhere
  # TODO: Check if the backend already exists? If so, check each requirement.
  def create_on_backend
    lab = Lab.find(self.lab_id)
    Rails.logger.info "Creating tenant #{self.name} on openstack backend #{lab.name}."

    # First, run through some checks to ensure we can create the whole tenant properly
    # Check if an external network exists
    admin_network_c = lab.get_neutron(lab.auth_tenant) 
    ext_network = admin_network_c.list_networks.select {|n| n.external == true}
    if ext_network.empty?
      Rails.logger.error "There are no external networks on the OpenStack host"
      return false
    end

    # Check if there are enough available floating ips
    # There does not appear to be an api endpoint to check ips available for an instance to check out
    # TODO - Take another look at this.

    # Create the tenant
    identity_c = get_connection("identity")
    identity_c.create_tenant({:name => self.name, :description => "Created by OpenShift Labs app", :enabled => true})
    tenant = identity_c.tenants.select {|t| t.name == self.name}.first
    if tenant.nil?
      Rails.logger.error "Attempted to create tenant with name #{self.name}, but tenant does not exist after creation."
      return false
    else
      Rails.logger.info "Created tenant #{self.name} with tenant id #{tenant.id}."
      self.uuid = tenant.id
    end

    # If any of the following fails, we need to be sure we delete the OpenStack backend tenant
    begin

      # Add the lab's user to the tenant
      # TODO the below assumes an admin role exists. Need to verify that this is always the case.
      role = identity_c.list_roles.select {|r| r[:name] == "admin"}.first
      admin_user = identity_c.list_users.select {|u| u.name == lab.username }.first
      Rails.logger.info "Adding user #{admin_user.name} to the #{self.name} tenant."
      identity_c.add_user_to_tenant({:tenant_id => tenant.id, :role_id => role[:id], :user_id => admin_user.id})

      # Get the compute and neutron connections
      compute_c = get_connection("compute")
      network_c = get_connection("network")

      # Set the quotas appropriately
      # Works needs to be done in the ruby-openstack gem to support this.
      Rails.logger.info "Setting #{self.name} tenant quotas."
      compute_c.set_limits(tenant.id, {:cores => lab.default_quota_cores,
                                       :floating_ips => lab.default_quota_instances,
                                       :instances => lab.default_quota_instances,
                                       :ram => lab.default_quota_ram
                                      })

      # Create a network
      network_name = self.name + "-network"
      Rails.logger.info "Creating network with name #{network_name} for tenant #{self.name}."
      network = network_c.create_network(network_name, {:admin_state_up => true})
      self.network = network_name

      # Create a subnet
      subnet_name = self.name + "-subnet"
      # TODO nameservers are hard-coded, but could change. Need to have them entered somewhere.
      Rails.logger.info "Creating subnet with name #{subnet_name} for tenant #{self.name}."
      subnet = network_c.create_subnet(network.id, "192.168.1.0/24", "4", {:name => subnet_name, :gateway_ip => "192.168.1.1", :enable_dhcp => true, :dns_nameservers => ['10.11.5.3', '10.11.5.4']})

      # Create a router and add interface to subnet
      router_name = self.name + "-router"
      # TODO we grab the first external network, we should have a user specify which one to use somewhere, in case there are multiple
      external_network = network_c.list_networks.select {|n| n.external == true }.first
      Rails.logger.info "Creating router with name #{router_name} for tenant #{self.name}."
      router = network_c.create_router(router_name, true, {:external_gateway_info => {:network_id => external_network.id}})
      Rails.logger.info "Adding router interface for subnet #{subnet_name} on router #{router_name}."
      network_c.add_router_interface(router.id, subnet.id)

      # Get the default security group
      # TODO we assume there is a default security group, probably not the best way to go about this.
      security_group = compute_c.security_groups.select {|k,v| v[:name] == "default"}
      self.security_group = "default"
      security_group_id = security_group.keys.first

      # Delete default security group rules
      Rails.logger.info "Removing default Ingress security group rules for tenant #{self.name}."
      security_group[security_group_id][:rules].each do |rule|
        compute_c.delete_security_group_rule(rule[:id])
      end

      # Create necessary security group rules
      Rails.logger.info "Creating all-open security groups rules for tcp, udp, and icmp on tenant #{self.name}"
      compute_c.create_security_group_rule(security_group_id, 
                                           {:ip_protocol => "tcp", :from_port => 1, :to_port => 65535, :cidr => "0.0.0.0/0"})
      compute_c.create_security_group_rule(security_group_id, 
                                           {:ip_protocol => "udp", :from_port => 1, :to_port => 65535, :cidr => "0.0.0.0/0"})
      compute_c.create_security_group_rule(security_group_id, 
                                           {:ip_protocol => "icmp", :from_port => -1, :to_port => -1, :cidr => "0.0.0.0/0"})

      # Allocate all necessary floating ips
      # TODO shouldn't just get the first pool, should have a dropdown and database entry in project
      Rails.logger.info "Allocating #{lab.default_quota_instances} floating ips to tenant #{self.name}"
      floating_ip_pool = compute_c.get_floating_ip_pools.first["name"]
      lab.default_quota_instances.times do
        compute_c.create_floating_ip(:pool => floating_ip_pool)
      end
 
      Rails.logger.info "Tenant #{self.name} creation completed."
    rescue => e
      Rails.logger.error "Could not create OpenStack backend tenant due to:"
      Rails.logger.error e.message
      Rails.logger.error e.backtrace
      destroy_backend
    end

  end

  # Delete the tenant on the OpenStack backend
  def destroy_backend
    Rails.logger.info "Removing tenant #{self.name} with tenant id #{self.uuid}."

    Rails.logger.info "Undeploying all instances for tenant #{self.name}..."
    # Delete all instances
    if self.instances.count > 0
      success = self.instances.each {|i| i.undeploy }
      if success
        Rails.logger.info "Removed all instances for tenant #{self.name}."
      else
        Rails.logger.error "Could not remove instance during project deletion:"
        Rails.logger.error "Instance: #{i.name} #{i.id} #{i.uuid}"
        return false
      end
    end

    compute_c = get_connection("compute")
    network_c = get_connection("network")
    identity_c = get_connection("identity")

    # Unallocate floating ips
    floating_ips = compute_c.get_floating_ips
    floating_ips.each do |ip|
      Rails.logger.info "Deleting floating ip #{ip.ip} with id #{ip.id}"
      compute_c.delete_floating_ip(ip.id)
    end

    routers = network_c.list_routers.select {|router| router.tenant_id == self.uuid}
    subnets = network_c.list_subnets.select {|subnet| subnet.tenant_id == self.uuid}
    networks = network_c.list_networks.select {|network| network.tenant_id == self.uuid}

    # Clear all router gateways
    routers.each do |router|
      Rails.logger.info "Clearing router gateway for #{router.name} with id #{router.id}."
      # Remove gateway from the router
      network_c.update_router(router.id, {"external_gateway_info" => {}})
    end

    # loop through each network
    # For each router, remove any subnet interfaces
    networks.each do |network|
      subnets.select {|subnet| subnet.network_id == network.id}.each do |subnet|
        routers.each do |router|
          begin
            Rails.logger.info "Attempting to remove router interface for subnet #{subnet.name} with id #{subnet.id} from router #{router.name} with id #{router.id}."
            network_c.remove_router_interface(router.id, subnet.id)
            Rails.logger.info "Successfully removed router interface for subnet #{subnet.name}."
          rescue => e
            Rails.logger.error "Tried to remove router interface for subnet #{subnet.name} with id #{subnet.id} from router #{router.name} with id #{router.id}."
          end
        end
      end
    end

    # Delete all subnets
    subnets.each do |subnet|
      Rails.logger.info "Deleting subnet #{subnet.name} with id #{subnet.id}"
      network_c.delete_subnet(subnet.id)
    end

    # Delete all routers
    routers.each do |router|
      Rails.logger.info "Deleting router #{router.name} with id #{router.id}"
      network_c.delete_router(router.id)
    end

    # Delete all networks
    networks.each do |network|
      Rails.logger.info "Deleting network #{network.name} with id #{network.id}"
      network_c.delete_network(network.id)
    end

    # Finally, delete the tenant
    Rails.logger.info "Deleting tenant #{self.name} with id #{self.uuid}"
    identity_c.delete_tenant(self.uuid)

    Rails.logger.info "Removal of tenant #{self.name} on the OpenStack backend succeeded."
  end

  def destroy_instances
    Rails.logger.info "Removing all instances in tenant"
    self.instances.each do |inst| 
      begin
        inst.destroy
      rescue => e
        Rails.logger.error "Could not remove instance #{inst.fqdn}: #{e.message}"
      end
    end
    Rails.logger.info "All instances removed"
  end

  def destroy_deployments
    Rails.logger.info "Removing all deployments created from tenant"
    self.deployments.each do |dep| 
      begin
        dep.destroy
      rescue => e
        Rails.logger.error "Could not remove deployment #{dep.id}: #{e.message}"
      end
    end
    Rails.logger.info "All deployments removed"
  end

end
