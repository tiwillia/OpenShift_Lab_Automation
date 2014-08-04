class Project < ActiveRecord::Base
  # attr_accessible :title, :body
 
  require 'base64'
 
  belongs_to :lab
  has_many :instances

  def start_all
    DEPLOYMENT_HANDLER.enqueue({:action => "start", :instances => self.instances, :project => self})
  end
  
  def stop_all
    DEPLOYMENT_HANDLER.enqueue({:action => "stop", :instances => self.instances, :project => self})
  end

  def start_one(id)
    # Get the connection and isntance
    c = get_connection
    q = get_connection("neutron")
    inst = Instance.find(id)

    # Get the image id
    image_id = c.images.select {|i| i[:name] == inst.image}.first[:id]
    if image_id.nil?
      Rails.logger.error "No image provided for instance: #{inst.fqdn} in project: #{self.name}."
      return false
    end

    # Get the flavor id
    flavor_id = c.flavors.select {|i| i[:name] == inst.flavor}.first[:id]
    if flavor_id.nil?
      Rails.logger.error "No flavor provided for instance: #{inst.fqdn} in project: #{self.name}."
      return false
    end

    # Get the network id
    network_id = q.networks.select {|n| n.name == self.network}.first.id
    if network_id.nil?
      Rails.logger.error "No network provided for instance: #{inst.fqdn} in project: #{self.name}."
      return false
    end

    # Get the floating ip id
    floating_ip_id = c.floating_ips.select {|f| f.ip == inst.floating_ip}.first.id

    # Get the security group
    sec_grp = self.security_group

    # Encode the cloud_init data
    cloud_init = Base64.encode64(inst.cloud_init)

    tries = 3
    begin
      server = c.create_server(:name => inst.name, :imageRef => image_id, :flavorRef => flavor_id, :security_groups => [sec_grp], :user_data => cloud_init, :networks => [{:uuid => network_id}])
    rescue => e
      tries -= 1
      if tries > 0
        retry
      else
        Rails.logger.error "Tried to start #{inst.fqdn} 3 times, failing each time. Giving up..."
        Rails.logger.error "Message: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace}"
        return false
      end
    end

    server_id = server.id
    server_status = server.status
    until server_status == "ACTIVE"
      Rails.logger.info "Waiting for #{inst.fqdn} to become active. Current status is \"#{server.status}\""
      sleep 3
      server_status = c.get_server(server.id).status
    end
    c.attach_floating_ip({:server_id => server_id, :ip_id => floating_ip_id})
    
    true 
    
  end

  def stop_one(id)
    c = get_connection
    inst = Instance.find(id)
    
    s = c.servers.select {|s| s[:name] == inst.name}.first
    s.delete! 
  end

  def restart_all
    start_all
    stop_all
  end
  
  def restart_one(id)
    start_one(id)
    stop_one(id)
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

private
  
  def get_connection(type = "compute")
    if type == "compute"
      Lab.find(self.lab_id).get_compute(self.name)
    else 
      Lab.find(self.lab_id).get_neutron(self.name)
    end 
  end

end
