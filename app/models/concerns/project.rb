module Project
  extend ActiveSupport::Concern

  included do
    belongs_to :lab
    has_many :deployments
    before_create :create_on_backend
    before_destroy :destroy_backend
    before_destroy :destroy_instances
    before_destroy :destroy_deployments
  end

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
    #TODO need to suppor v3 single deployments
    deployment = self.deployments.new(:action => "single_deployment", :v2_instance_id => instance_id, :complete => false, :started_by => user_id)
    if deployment.save
      find_instance(instance_id).update_attributes(:deployment_started => true, :deployment_completed => false)
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

  def redeploy_all(user_id)
    deployment = self.deployments.new(:action => "redeploy", :complete => false, :started_by => user_id)
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
    instances.each do |i|
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
    instances.each do |i|
      next if i.deployment_completed && !i.deployment_started
      all_deployed = false
      break
    end
    all_deployed
  end

  def none_deployed?
    none_deployed = true
    instances.each do |i|
      next if !i.deployment_completed && !i.deployment_started
      none_deployed = false
      break
    end
    none_deployed
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
    instances.each do |i|
      if not i.update_attributes(:deployment_completed => false, :deployment_started => false, :reachable => false)
        Rails.logger.error "Unable to update instance after destroying on backend: #{i.inspect}"
        return false
      end
    end
    return true
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

  # Check if project has been checked out for at least 7 days
  def inactive?
    return false unless self.checked_out?
    return false if self.hidden
    (Date.today - self.checked_out_at.to_date) >= 7
  end

  def user_can_edit?(user)
    if user && (user.admin? || self.checked_out_by == user.id)
      return true
    else
      return false
    end
  end

  def flavors
    c = get_connection
    flav_a = c.flavors.map {|f| f[:name] }
    flav_a.sort
  end

  def images
    c = get_connection
    image_a = c.images.map {|i| i[:name]}
    image_a.sort
  end

  def floating_ips
    c = get_connection
    ip_a = c.floating_ips.map {|i| i.ip}
    ip_a.sort_by {|ip| ip.split('.').last.to_i }
  end

  # Returns only volume display names
  def volumes
    c = get_connection("cinder")
    vol_a = c.volumes.map {|v| v.display_name}
  end

  def volumes_full
    c = get_connection("cinder")
    c.volumes
  end

  # size is in GiB
  def create_volume(display_name, size)
    c = get_connection("cinder")
    begin
      vol = c.create_volume({:display_name => display_name, :size => size})
      until vol.status == "available"
        vol = c.get_volume(vol.id)
      end
    rescue => e
      Rails.logger.error "Could not create volume for project #{self.name} with size #{size}GiB and display name #{display_name}"
      Rails.logger.error e.message
      Rails.logger.error e.backtrace
      return false
    end
    vol
  end

  # display_name, for instances, is always instance.id + "_" + instance.name
  def delete_volume(id)
    c = get_connection("cinder")
    vol = c.get_volume(id)
    begin
      vol = c.delete_volume(id)
    rescue => e
      Rails.logger.error "Could not delete volume for project #{self.name} with display name #{display_name}"
      Rails.logger.error e.message
      Rails.logger.error e.backtrace
      return false
    end if vol.present?
    true
  end

  def get_volume(id)
    c = get_connection("cinder")
    begin
      c.get_volume(id)
    rescue
      Rails.logger.error "Could not find volume with id #{opt[:id]}"
      nil
    end
  end

  def get_volume_by_display_name(display_name)
    c = get_connection("cinder")
    vol = c.volumes.select {|v| v.display_name == opt[:display_name] }
    nil unless vol.present?
  end

  def available_floating_ips
    self.floating_ips - instances.map {|i| i.floating_ip }
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
    when "compute", "nova"
      Lab.find(self.lab_id).get_compute(self.name)
    when "identity", "keystone"
      Lab.find(self.lab_id).get_keystone
    when "network", "neutron"
      Lab.find(self.lab_id).get_neutron(self.name)
    when "volume", "cinder"
      Lab.find(self.lab_id).get_cinder(self.name)
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
    destroy_instances

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

  def destroy_instances
    Rails.logger.info "Removing all instances in tenant"
    c = self.get_connection
    c.servers.each do |s|
      server = c.get_server(s[:id])
      if !server.delete!
        Rails.logger.error "Unable to delete server on backend: #{server.inspect}"
        return false
      end
    end
    instances.each do |inst|
      begin
        inst.destroy
      rescue => e
        Rails.logger.error "Could not remove instance #{inst.fqdn}: #{e.message}"
      end
    end
    Rails.logger.info "All instances removed"
  end

end
