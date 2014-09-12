class Project < ActiveRecord::Base
  # attr_accessible :title, :body
 
  require 'base64'
 
  belongs_to :lab
  has_many :instances
  has_many :deployments

  validates :name,:network,:security_group,:domain,:lab,:ose_version, presence: true

  def start_all
    deployment = self.deployments.new(:action => "build")
    if deployment.save
      deployment.begin
      return true
    else
      return false
    end
  end
  
  def stop_all
    deployment = self.deployments.new(:action => "tear_down")
    if deployment.save
      deployment.begin
      return true
    else
      return false
    end
  end

  def restart_all
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
 
  def details
    return nil if not self.ready?
    
    gear_sizes = Array.new
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
      if inst.types.include?("node")
        gear_sizes << inst.gear_size
        node_hostname = inst.fqdn
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

      named_entry = inst.name + ":" + inst.floating_ip
      named_entries << named_entry
    end

    valid_gear_sizes = gear_sizes.uniq

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
    limits = self.limits
    if limits[:max_instances] < self.instances.count
      return false, "There are more #{self.instances.count - limits[:max_instances]} more instances than the project limit of \"#{limits[:max_instances]}\" allows."
    end
    types.uniq!
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

end
