class Project < ActiveRecord::Base
  # attr_accessible :title, :body
 
  require 'base64'
 
  belongs_to :lab
  has_many :instances
  has_many :deployments

  validates :name,:network,:security_group,:domain,:lab,:ose_version, presence: true

  before_create :set_uuid

  def deploy_all
    deployment = self.deployments.new(:action => "build", :complete => false)
    if deployment.save
      deployment.begin
      return true
    else
      return false
    end
  end
 
  def deploy_one(instance_id)
    deployment = self.deployments.new(:action => "single_deployment", :instance_id => instance_id, :complete => false)
    if deployment.save
      Instance.find(instance_id).update_attributes(:deployment_started => true, :deployment_completed => false)
      deployment.begin
      return true
    else
      return false
    end
  end

  def undeploy_all
    deployment = self.deployments.new(:action => "tear_down", :complete => false)
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
    deployment = self.deployments.new(:action => "redploy")
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
    q = get_connection("neutron")
    
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
    if type == "compute"
      Lab.find(self.lab_id).get_compute(self.name)
    else 
      Lab.find(self.lab_id).get_neutron(self.name)
    end 
  end

  private
    
  def set_uuid
    c = get_connection
    path = c.instance_variable_get("@connection").instance_variable_get("@service_path")
    id = path.split("/").last
    self.uuid = id
  end

end
