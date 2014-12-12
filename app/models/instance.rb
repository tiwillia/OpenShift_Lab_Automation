class Instance < ActiveRecord::Base
  # attr_accessible :title, :body

  belongs_to :project

  serialize :types
  serialize :install_variables

  before_save :determine_fqdn
  before_save :ensure_types_exists

  validates :name, :floating_ip, :root_password, :flavor, :image, :project, presence: true
  validates :root_password, length: { minimum: 3 }

  # Returns true or false
  # If false, also returns error message
  def reachable?
    self.update_attributes(:last_checked_reachable => DateTime.now)
    Rails.logger.debug "Checking reachability for instance #{self.fqdn}"
    begin
      Timeout::timeout(10) {
        ssh = Net::SSH.start(self.floating_ip, 'root', :password => self.root_password, :paranoid => false, :timeout => 5)
        ssh.exec!("hostname")
      }
    rescue => e
      Rails.logger.error "Could not reach instance #{self.fqdn} due to: #{e.message}"
      Rails.logger.error e.backtrace
      self.update_attributes(:reachable => false)
      message = e.message
      message = "Timeout - SSH operation took longer than 10 seconds" if e.message == "execution expired"
      return false, message
    end
    self.update_attributes(:reachable => true)
    Rails.logger.debug "Successfully reached instance #{self.fqdn}"
    true
  end

  def deployed?
    p = Project.find(self.project_id)
    c = p.get_connection

    servers = c.servers.map {|s| s[:name]} 
    deployed = (servers.include? self.name)
    deployed
  end

  def install_log
    if self.reachable?
      begin 
        Timeout::timeout(10) {
          ssh = Net::SSH.start(self.floating_ip, 'root', :password => self.root_password, :paranoid => false, :timeout => 5)
          log_text = ssh.exec!("cat /root/.install_log")
          return log_text
        }
      rescue => e
        Rails.logger.error "Could not get installation log for instance #{self.fqdn} due to: #{e.message}"
        Rails.logger.error e.backtrace
        return false, "Could not get installation log for instance #{self.fqdn} due to: #{e.message}"
      end
    else
      return false, "Unable to connect to #{self.fqdn} via ssh."
    end
  end

  def deploy(deployment_id)
    # Get the connection and instance
    p = Project.find(self.project_id)
    c = p.get_connection
    q = p.get_connection("neutron")

    # Get the image id
    image_id = c.images.select {|i| i[:name] == self.image}.first[:id]
    if image_id.nil?
      Rails.logger.error "No image provided for instance: #{self.fqdn} in project: #{p.name}."
      return false
    end

    # Get the flavor id
    flavor_id = c.flavors.select {|i| i[:name] == self.flavor}.first[:id]
    if flavor_id.nil?
      Rails.logger.error "No flavor provided for instance: #{self.fqdn} in project: #{p.name}."
      return false
    end

    # Get the network id
    network_id = q.networks.select {|n| n.name == p.network}.first.id
    if network_id.nil?
      Rails.logger.error "No network provided for instance: #{self.fqdn} in project: #{p.name}."
      return false
    end

    # Get the floating ip id
    floating_ip_id = c.floating_ips.select {|f| f.ip == self.floating_ip}.first.id

    # Get the security group
    sec_grp = p.security_group

    # Encode the cloud_init data
    if self.no_openshift
      cloud_init = Base64.encode64(self.cloud_init_blank(deployment_id))
    else
      cloud_init = Base64.encode64(self.cloud_init(deployment_id))
    end

    tries = 3
    begin
        server = c.create_server(:name => self.name, :imageRef => image_id, :flavorRef => flavor_id, :security_groups => [sec_grp], :user_data => cloud_init, :networks => [{:uuid => network_id}])
    rescue => e
      tries -= 1
      if tries > 0
        retry
      else
        Rails.logger.error "Tried to start #{self.fqdn} 3 times, failing each time. Giving up..."
        Rails.logger.error "Message: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace}"
        return false
      end
    end

    server_id = server.id
    server_status = server.status
    until server_status == "ACTIVE"
      Rails.logger.debug "Waiting for #{self.fqdn} to become active. Current status is \"#{server.status}\""
      sleep 3
      server_status = c.get_server(server.id).status
    end
    c.attach_floating_ip({:server_id => server_id, :ip_id => floating_ip_id})

    true
  
  end

  def undeploy
    p = Project.find(self.project_id)
    c = p.get_connection
    s = c.servers.select {|s| s[:name] == self.name}.first
    server = c.get_server(s[:id])
    if server.delete!
      self.update_attributes(:deployment_completed => false, :deployment_started => false, :reachable => false)
      return true
    else
      return false
    end
  end

  def cloud_init_blank(deployment_id)
    cinit=<<EOF
#cloud-config               
# vim:syntax=yaml
hostname: #{self.safe_name}
fqdn: #{self.fqdn}
manage_etc_hosts: true
debug: True
ssh_pwauth: True
disable_root: false
chpasswd:
  list: |
    root:#{self.root_password}
    cloud-user:test
  expire: false
runcmd:
- echo "$(date) - Instance initialized and deployed, starting setup through cloud-init." >> /root/.install_log
#The MTU is necessary
- echo "MTU=1450" >> /etc/sysconfig/network-scripts/ifcfg-eth0
- service network restart
- echo "$(date) - MTU for eth0 set to 1450 to behave well with the OpenStack neutron backend." >> /root/.install_log
- sed -i'.orig' -e's/without-password/yes/' /etc/ssh/sshd_config
- echo $'StrictHostKeyChecking no\\nUserKnownHostsFile /dev/null' >> /etc/ssh/ssh_config
- service sshd restart
- echo "$(date) - SSH server configuration changed to allow root to login with a password." >> /root/.install_log
- curl #{CONFIG[:URL]}/ose_files/bashrc > /root/.bashrc
- curl #{CONFIG[:URL]}/ose_files/bash_profile > /root/.bash_profile
- curl #{CONFIG[:URL]}/ose_files/vimrc > /root/.vimrc
- curl #{CONFIG[:URL]}/ose_files/authorized_keys > /root/.ssh/authorized_keys
- curl #{CONFIG[:URL]}/ose_files/voyager.pub > /root/.ssh/id_rsa.pub
- curl #{CONFIG[:URL]}/ose_files/voyager.pri > /root/.ssh/id_rsa
- echo "$(date) - Downloaded bashrc, authorized_keys, vimrc, openshift.sh script, and other necessary items." >> /root/.install_log
- chmod 0600 /root/.ssh/id_rsa
- chmod 0600 /root/.ssh/id_rsa.pub
- mkdir -p /etc/pki/product
- curl #{CONFIG[:URL]}/ose_files/69.pem > /etc/pki/product/69.pem
- echo "$(date) - Downloaded and installed Red Hat Enterprise Linux Server (6.5) product key." >> /root/.install_log
- exit_code=255; while [ $exit_code != 0 ]; do echo "$(date) - Attempting to register with RHSM." >> /root/.install_log; subscription-manager register --username=#{CONFIG[:rhsm_username]} --password=#{CONFIG[:rhsm_password]} --name=#{self.safe_name} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Registered via RHSM with username #{CONFIG[:rhsm_username]} and server name #{self.safe_name}." >> /root/.install_log
- exit_code=255; while [ $exit_code == 255 ]; do echo "$(date) - Attempting to attach subscription with pool id #{CONFIG[:rhsm_pool_id]}..." >> /root/.install_log; subscription-manager attach --pool #{CONFIG[:rhsm_pool_id]} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Attached pool id #{CONFIG[:rhsm_pool_id]}" >> /root/.install_log
- subscription-manager repos --disable=* &>> /root/.rhsm_output
- subscription-manager repos --enable=rhel-6-server-rpms &>> /root/.rhsm_output
- echo "$(date) - Enabled repositories = rhel-6-server-rpms" >> /root/.install_log
- curl #{CONFIG[:URL]}/instances/#{self.id}/callback_script?deployment_id=#{deployment_id} > /root/.install_handler.sh
- echo "$(date) - Called to labs application to generate and download the installation handler script." >> /root/.install_log
- sh /root/.install_handler.sh
- echo "$(date) - Deployment completed." >> /root/.install_log
EOF
  end

  # Generate cloudinit details 
  def cloud_init(deployment_id)

    ose_version = Project.find(self.project_id).ose_version

    # Establish the base
    cinit=<<EOF
#cloud-config               
# vim:syntax=yaml
hostname: #{self.safe_name}
fqdn: #{self.fqdn}
manage_etc_hosts: true
debug: True
ssh_pwauth: True
disable_root: false
chpasswd:
  list: |
    root:#{self.root_password}
    cloud-user:test
  expire: false
runcmd:
- echo "$(date) - Instance initialized and deployed, starting setup through cloud-init." >> /root/.install_log
#The MTU is necessary
- echo "MTU=1450" >> /etc/sysconfig/network-scripts/ifcfg-eth0
- service network restart
- echo "$(date) - MTU for eth0 set to 1450 to behave well with the OpenStack neutron backend." >> /root/.install_log
- sed -i'.orig' -e's/without-password/yes/' /etc/ssh/sshd_config
- echo $'StrictHostKeyChecking no\\nUserKnownHostsFile /dev/null' >> /etc/ssh/ssh_config
- service sshd restart
- echo "$(date) - SSH server configuration changed to allow root to login with a password." >> /root/.install_log
- curl https://raw.githubusercontent.com/openshift/openshift-extras/enterprise-#{ose_version}/enterprise/install-scripts/generic/openshift.sh > /root/openshift.sh
- curl #{CONFIG[:URL]}/ose_files/bashrc > /root/.bashrc
- curl #{CONFIG[:URL]}/ose_files/bash_profile > /root/.bash_profile
- curl #{CONFIG[:URL]}/ose_files/vimrc > /root/.vimrc
- curl #{CONFIG[:URL]}/ose_files/authorized_keys > /root/.ssh/authorized_keys
- curl #{CONFIG[:URL]}/ose_files/voyager.pub > /root/.ssh/id_rsa.pub
- curl #{CONFIG[:URL]}/ose_files/voyager.pri > /root/.ssh/id_rsa
- echo "$(date) - Downloaded bashrc, authorized_keys, vimrc, openshift.sh script, and other necessary items." >> /root/.install_log
- chmod 0600 /root/.ssh/id_rsa
- chmod 0600 /root/.ssh/id_rsa.pub
- mkdir -p /etc/pki/product
- curl #{CONFIG[:URL]}/ose_files/69.pem > /etc/pki/product/69.pem
- echo "$(date) - Downloaded and installed Red Hat Enterprise Linux Server (6.5) product key." >> /root/.install_log
- curl #{CONFIG[:URL]}/instances/#{self.id}/callback_script?deployment_id=#{deployment_id} > /root/.install_handler.sh
- echo "$(date) - Called to labs application to generate and download the installation handler script." >> /root/.install_log
- exit_code=255; while [ $exit_code != 0 ]; do echo "$(date) - Attempting to register with RHSM." >> /root/.install_log; subscription-manager register --username=#{CONFIG[:rhsm_username]} --password=#{CONFIG[:rhsm_password]} --name=#{self.safe_name} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Registered via RHSM with username #{CONFIG[:rhsm_username]} and server name #{self.safe_name}." >> /root/.install_log
- exit_code=255; while [ $exit_code == 255 ]; do echo "$(date) - Attempting to attach subscription with pool id #{CONFIG[:rhsm_pool_id]}..." >> /root/.install_log; subscription-manager attach --pool #{CONFIG[:rhsm_pool_id]} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Attached pool id #{CONFIG[:rhsm_pool_id]}" >> /root/.install_log
- subscription-manager repos --disable=* &>> /root/.rhsm_output
EOF
  
    # Enable repositories and install oo-admin-yum-validator
    if self.types.include?("broker") || self.types.include?("named") || self.types.include?("activemq") || self.types.include?("mongodb")
      cinit = cinit + <<EOF
- subscription-manager repos --enable=rhel-6-server-rpms --enable=rhel-6-server-ose-#{ose_version}-infra-rpms --enable rhel-6-server-ose-#{ose_version}-rhc-rpms &>> /root/.rhsm_output
- echo "$(date) - Enabled repositories = rhel-6-server-rpms rhel-6-server-ose-#{ose_version}-infra-rpms rhel-6-server-ose-#{ose_version}-rhc-rpms" >> /root/.install_log
EOF
    end
    
    if self.types.include?("node")
      cinit = cinit + <<EOF
- subscription-manager repos --enable=rhel-6-server-rpms --enable=rhel-6-server-ose-#{ose_version}-node-rpms --enable=jb-ews-2-for-rhel-6-server-rpms --enable=rhel-6-server-ose-#{ose_version}-jbosseap-rpms --enable=rhel-server-rhscl-6-rpms --enable=jb-eap-6-for-rhel-6-server-rpms &>> /root/.rhsm_output
- echo "$(date) - Enabled repositories = rhel-6-server-rpms rhel-6-server-ose-#{ose_version}-node-rpms jb-ews-2-for-rhel-6-server-rpms rhel-6-server-ose-#{ose_version}-jbosseap-rpms rhel-server-rhscl-6-rpms jb-eap-6-for-rhel-6-server-rpms" >> /root/.install_log
EOF
    end

    cinit = cinit + <<EOF
- echo "$(date) - Installing openshift-enterprise-release..." >> /root/.install_log
- yum install openshift-enterprise-release -y
- echo "$(date) - Installation of openshift-enterprise-release succeeded." >> /root/.install_log
EOF

    # Validate and fix repository priorities as needed
    if self.types.include?("node")
      if self.types == ["node"]
        cinit = cinit + <<EOF
- echo "$(date) - Running oo-admin-yum-validator for OSE version #{ose_version}." >> /root/.install_log
- oo-admin-yum-validator --oo-version #{ose_version} -r node -r node-eap --fix-all
EOF
      else
        cinit = cinit + <<EOF
- echo "$(date) - Running oo-admin-yum-validator for OSE version #{ose_version}." >> /root/.install_log
- oo-admin-yum-validator --oo-version #{ose_version} -r node -r node-eap -r broker -r client --fix-all
EOF
      end
    else
      cinit = cinit + <<EOF
- echo "$(date) - Running oo-admin-yum-validator for OSE version #{ose_version}." >> /root/.install_log
- oo-admin-yum-validator --oo-version #{ose_version} -r broker -r client --fix-all
EOF
    end

    # Update, install extra rpms
    cinit = cinit + <<EOF
- echo "$(date) - Completely updating system and installing extra packages..." >> /root/.install_log
- yum update -y
- yum install sysstat lsof wget vim-enhanced mlocate nmap -y
- echo "$(date) - System update completed." >> /root/.install_log
- echo "$(date) - Generating installation variables into file /root/.install_variables." >> /root/.install_log
EOF

    if ose_version == "2.0"
      # BUGFIX for http://post-office.corp.redhat.com/archives/openshift-sme/2014-October/msg00209.html
      cinit = cinit + <<EOF
- echo "protected_multilib=false" >> /etc/yum.conf
EOF
    end

    # Add all variables generated for install script
    vars = generate_variables
    vars.each do |key,value|
      cinit = cinit + <<EOF
- echo 'export #{key}="#{value}"' >> /root/.install_variables
EOF
    end
    cinit = cinit + <<EOF
- echo "$(date) - Sourcing environment variables...." >> /root/.install_log
- source /root/.install_variables
- echo "$(date) - Sourcing environment variables completed, as a test | CONF_DOMAIN = $CONF_DOMAIN" >> /root/.install_log
EOF

    # Run the script! Woo!
    cinit = cinit + <<EOF
- echo "$(date) - Running openshift installation handler..." >> /root/.install_log
- echo "STARTED" > /root/.install_tracker
- sh /root/.install_handler.sh
- echo "$(date) - Installation procedure finished." >> /root/.install_log
EOF

    # Do some extra jazz requried for nodes
    if self.types.include?("node")
      cinit = cinit + <<EOF
- echo "$(date) - Setting PUBLIC_IP and PUBLIC_HOSTNAME in /etc/openshift/node.conf" >> /root/.install_log
- sed -i "s/PUBLIC_IP=[0-9\.]*/PUBLIC_IP=#{self.floating_ip}/" /etc/openshift/node.conf
- sed -i "s/PUBLIC_HOSTNAME=.*/PUBLIC_HOSTNAME=#{self.fqdn}/" /etc/openshift/node.conf
- echo "$(date) - PUBLIC_IP=#{self.floating_ip} and PUBLIC_HOSTNAME=#{self.fqdn}" >> /root/.install_log
EOF
      if ose_version == "2.0"
        if self.gear_size != "small" && self.gear_size != ""
          cinit = cinit + <<EOF
  - sed -i "s/node_profile=small/node_profile=#{self.gear_size}/" /etc/openshift/resource_limits.conf
EOF
        end
      end
    end

  # Download extra tools to the broker only
    if self.types.include?("broker")
      cinit = cinit + <<EOF
- echo "$(date) - Downloading several extra tools to the /root/TOOLS directory." >> /root/.install_log
- mkdir /root/TOOLS
- curl #{CONFIG[:URL]}/ose_files/stress_test.rb > /root/TOOLS/stress_test.rb
- curl #{CONFIG[:URL]}/ose_files/find_master.sh > /root/TOOLS/find_master.sh
- curl #{CONFIG[:URL]}/ose_files/node_gear_count.sh > /root/TOOLS/node_gear_count.sh
- curl -k https://raw.githubusercontent.com/openshift/openshift-extras/enterprise-#{ose_version}/admin/reset_deployment.rb > /root/TOOLS/reset_deployment.sh
EOF
    end
    
    # Reboot all systems after install
    cinit = cinit + <<EOF
- echo "$(date) - Deployment completed, rebooting..." >> /root/.install_log
- echo "DONE" > /root/.install_tracker
- reboot
EOF

    cinit
  end 
 
  def safe_name
    self.name.gsub(/[\s\W]/, "_")
  end

private

  # Create FQDN
  def determine_fqdn
    fqdn = self.safe_name + "." + Project.find(self.project_id).domain
    self.fqdn = fqdn
  end

  # Generate Installation script variables
  def generate_variables
    # Possible (2.1) variables:
      # CONF_INSTALL_COMPONENTS="node"
      # CONF_NO_JBOSSEWS=1
      # CONF_NO_JBOSSEAP=1
      # CONF_INSTALL_METHOD="yum"
      # CONF_OPTIONAL_REPO=1
      # CONF_ACTIONS=do_all_actions,configure_datastore_add_replicants
      # CONF_DOMAIN="example.com"
      # CONF_HOSTS_DOMAIN="hosts.example.com"
      # CONF_NAMED_ENTRIES="broker:192.168.0.1,node:192.168.0.2"
      # CONF_NAMED_IP_ADDR=10.10.10.10
      # CONF_BIND_KEY=""
      # CONF_BIND_KRB_KEYTAB=""
      # CONF_BIND_KRB_PRINCIPAL=""
      # CONF_BROKER_IP_ADDR=10.10.10.10
      # CONF_NODE_IP_ADDR=10.10.10.10
      # CONF_KEEP_HOSTNAME=true
      # CONF_KEEP_NAMESERVERS=true
      # CONF_FORWARD_DNS=false
      # CONF_NODE_V1_ENABLE=false
      # CONF_NO_NTP=true
      # CONF_ACTIVEMQ_REPLICANTS="activemq01.example.com,activemq02.example.com"
      # CONF_ACTIVEMQ_ADMIN_PASSWORD="ChangeMe"
      # CONF_ACTIVEMQ_AMQ_USER_PASSWORD="ChangeMe"
      # CONF_MCOLLECTIVE_USER="mcollective"
      # CONF_MCOLLECTIVE_PASSWORD="mcollective"
      # CONF_MONGODB_NAME="openshift_broker"
      # CONF_MONGODB_BROKER_USER="openshift"
      # CONF_MONGODB_BROKER_PASSWORD="mongopass"
      # CONF_MONGODB_ADMIN_USER="admin"
      # CONF_MONGODB_ADMIN_PASSWORD="mongopass"
      # CONF_ACTIONS=do_all_actions,configure_datastore_add_replicants
      # CONF_DATASTORE_REPLICANTS="datastore01.example.com:27017,datastore02.example.com:27017,datastore03.example.com:27017"
      # CONF_MONGODB_REPLSET="ose"
      # CONF_MONGODB_KEY="OSEnterprise"
      # CONF_OPENSHIFT_USER1="demo"
      # CONF_OPENSHIFT_PASSWORD1="changeme"
      # CONF_BROKER_AUTH_SALT=""
      # CONF_BROKER_SESSION_SECRET=""
      # CONF_CONSOLE_SESSION_SECRET=""
      # CONF_VALID_GEAR_SIZES="small"
      # CONF_BROKER_KRB_SERVICE_NAME=""
      # CONF_BROKER_KRB_AUTH_REALMS=""
      # CONF_NODE_PROFILE

    variables = Hash.new
    project = Project.find(self.project_id)
    project_details = project.details
    ose_version = project.ose_version
    return nil if project_details.nil?
    variables = { :CONF_DOMAIN => project_details[:domain],
                  :CONF_NAMED_IP_ADDR => project_details[:named_ip],
                  :CONF_NAMED_HOSTNAME => project_details[:named_hostname],
                  :CONF_DATASTORE_HOSTNAME => project_details[:datastore_replicants].first,
                  :CONF_ACTIVEMQ_HOSTNAME => project_details[:activemq_replicants].first,
                  :CONF_BROKER_HOSTNAME => project_details[:broker_hostname],
                  :CONF_NODE_HOSTNAME => project_details[:node_hostname],
                  :CONF_INSTALL_COMPONENTS => self.types.join(","),
                  :CONF_INSTALL_METHOD => "none",
                  :CONF_KEEP_HOSTNAME => "true",
                  :CONF_MCOLLECTIVE_USER => project_details[:mcollective_username],
                  :CONF_MCOLLECTIVE_PASSWORD => project_details[:mcollective_password],
                  :CONF_MONGODB_BROKER_USER => project_details[:mongodb_username],
                  :CONF_MONGODB_BROKER_PASSWORD => project_details[:mongodb_password],
                  :CONF_MONGODB_ADMIN_USER => project_details[:mongodb_admin_username],
                  :CONF_MONGODB_ADMIN_PASSWORD => project_details[:mongodb_admin_password],
                  :CONF_ACTIVEMQ_ADMIN_PASSWORD => project_details[:activemq_admin_password],
                  :CONF_ACTIVEMQ_AMQ_USER_PASSWORD => project_details[:activemq_user_password],
                  :CONF_OPENSHIFT_USER1 => project_details[:openshift_username],
                  :CONF_OPENSHIFT_PASSWORD1 => project_details[:openshift_password],
                  :CONF_BIND_KEY => project_details[:bind_key], 
                  :CONF_VALID_GEAR_SIZES => project_details[:valid_gear_sizes].join(","),
                  :CONF_ACTIONS => "do_all_actions"}
 
    if self.types.include?("named")
      variables[:CONF_NAMED_ENTRIES] = project_details[:named_entries].join(",")
    end
 
    if self.types.include?("node")
      variables[:CONF_NODE_PROFILE] = self.gear_size
      variables[:CONF_NODE_PROFILE_NAME] = self.gear_size if ose_version.to_f >= 2.2
    end


    if project_details[:datastore_replicants].count > 2
      variables[:CONF_DATASTORE_REPLICANTS] = project_details[:datastore_replicants].join(",")
      variables[:CONF_MONGODB_KEY] = "lolMongodbIsWack"
      variables[:CONF_MONGODB_REPLSET] = "ose"
    end

    if project_details[:activemq_replicants].count > 1
      variables[:CONF_ACTIVEMQ_REPLICANTS] = project_details[:activemq_replicants].join(",")
    end

    if ose_version.to_f >= 2.1
      variables[:CONF_NO_SCRAMBLE] = "true"
      variables[:CONF_CARTRIDGES] = "standard,jbosseap,jbossews,fuse,amq"
    end

    # Blank variables will break an installation.
    variables.each do |key, value|
      if value.nil? || value == ""
        Rails.logger.error "Instance with id #{self.id} and fqdn #{self.fqdn} includes a blank variable: #{key.to_s}"
        Rails.logger.error "Removing key #{key.to_s}"
        variables.delete(key)
      end
    end

    return variables

  end

  def ensure_types_exists
    if self.types.nil?
      self.types = []
    else
      self.types = self.types.flatten.uniq
    end 
  end

end
