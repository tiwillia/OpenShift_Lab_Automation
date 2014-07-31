class Project < ActiveRecord::Base
  # attr_accessible :title, :body
  
  belongs_to :lab
  has_many :instances

  def start_all
  end
  
  def stop_all
  end

  def start_one(id)
    c = get_connection
  end

  def stop_one(id)
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
  
    self.instances.each do |inst|

      if inst.types.include?("named")
        named_instance = inst
        named_ip = named_instance.floating_ip
        named_hostname = named_instance.fqdn
      end
      if inst.types.include?("node")
        gear_sizes << inst.gear_size
      end
      if inst.types.include?("datastore")
        datastore_replicants << inst.fqdn
      end
      if inst.types.include?("activemq")
        activemq_replicants << inst.fqdn
      end
      
      named_entry = inst.name + ":" + inst.floating_ip
      named_entries << named_entry
    end
    valid_gear_sizes = gear_sizes.uniq

    return {:named_ip => named_ip, 
            :named_hostname => named_hostname, 
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
    types = Array.new
    self.instances.each do |inst|
      types << inst.types
    end
    types.flatten!
    duplicates = types.select{|t| types.count(t) > 1}
    if duplicates.include?("named")
      return false  # If named is included more than once
    end
    if duplicates.include?("datastore") && duplicates.count("datastore") < 3
      return false # If there are more than one, but less than 3 mongodb hosts.
    end
    types.uniq!
    if types == ["named", "broker", "datastore", "activemq", "node"]
      true
    else
      false # If one or more of the components are missing
    end
  end

private
  
  def get_connection
    Lab.find(self.lab_id).get_connection
  end

end
