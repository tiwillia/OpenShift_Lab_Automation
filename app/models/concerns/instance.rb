module Instance
  extend ActiveSupport::Concern

  included do
    before_save :determine_fqdn
  end

  def safe_name
    self.name.gsub(/[\s\W]/, "_")
  end

  def deploy(deployment_id)
    # Get the connection and instance
    c = project.get_connection
    q = project.get_connection("network")

    # Get the image id
    image = c.images.select {|i| i[:name] == self.image}.first
    if image.nil?
      Rails.logger.error "No image provided for instance: #{self.fqdn} in project: #{p.name}."
      return false
    else
      image_id = image[:id]
    end

    # Get the flavor id
    flavor = c.flavors.select {|i| i[:name] == self.flavor}.first
    if flavor.nil?
      Rails.logger.error "No flavor provided for instance: #{self.fqdn} in project: #{p.name}."
      return false
    else
      flavor_id = flavor[:id]
    end

    # Get the network id
    network = q.networks.select {|n| n.name == p.network}.first
    if network.nil?
      Rails.logger.error "No network provided for instance: #{self.fqdn} in project: #{p.name}."
      return false
    else
      network_id = network.id
    end

    # Get the floating ip id
    floating_ip = c.floating_ips.select {|f| f.ip == self.floating_ip}.first
    if floating_ip.nil?
      Rails.logger.error "Could not get a floating ip for instance: #{self.fqdn} in project: #{p.name}."
      return false
    else
      floating_ip_id = floating_ip.id
    end

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
    until server.status == "ACTIVE"
      Rails.logger.debug "Waiting for #{self.fqdn} to become active. Current status is \"#{server.status}\""
      sleep 3
      server = c.get_server(server.id)
    end
    c.attach_floating_ip({:server_id => server_id, :ip_id => floating_ip_id})

    self.update_attributes(:uuid => server_id, :internal_ip => server.accessipv4)

    true

  end

  def undeploy
    c = project.get_connection
    s = c.servers.select {|s| s[:id] == self.uuid}.first
    if s.nil?
      Rails.logger.warn "Attempted to undeploy an instance that does not exist on the backend: #{self.inspect}"
      return true
    end
    server = c.get_server(s[:id])
    if server.delete!
      self.update_attributes(:deployment_completed => false, :deployment_started => false, :reachable => false, :uuid => nil, :internal_ip => nil)
      return true
    else
      return false
    end
  end

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
    c = project.get_connection

    servers = c.servers.map {|s| s[:name]}.
    deployed = (servers.include? self.name)
    deployed
  end

  def get_console
    if self.uuid
      c = project.get_connection
      begin
        console_url = c.get_console({:server_id => self.uuid})
      rescue => e
        return false, e.message
      end
      return true, console_url
    else
      return false, "Instance is not deployed, or does not have a uuid properly defined".
    end
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

  def cloud_init_blank(deployment_id)
    cinit=<<EOF
#cloud-config...............
# vim:syntax=yaml
hostname: #{self.safe_name}
fqdn: #{self.fqdn}
manage_etc_hosts: false
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
- exit_code=255; while [ $exit_code != 0 ]; do echo "$(date) - Attempting to register with RHSM. Previous exit code  $exit_code" >> /root/.install_log; subscription-manager register --force --username=#{CONFIG[:rhsm_username]} --password=#{CONFIG[:rhsm_password]} --name=#{self.safe_name} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Registered via RHSM with username #{CONFIG[:rhsm_username]} and server name #{self.safe_name}." >> /root/.install_log
- exit_code=255; while [ $exit_code == 255 ]; do echo "$(date) - Attempting to attach subscription with pool id #{CONFIG[:rhsm_pool_id]}. Previous exit code  $exit_code" >> /root/.install_log; subscription-manager attach --pool #{CONFIG[:rhsm_pool_id]} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Attached pool id #{CONFIG[:rhsm_pool_id]}" >> /root/.install_log
- subscription-manager repos --disable=* &>> /root/.rhsm_output
- subscription-manager repos --enable=rhel-6-server-rpms &>> /root/.rhsm_output
- echo "$(date) - Enabled repositories = rhel-6-server-rpms" >> /root/.install_log
- curl #{CONFIG[:URL]}/v2_instances/#{self.id}/callback_script?deployment_id=#{deployment_id} > /root/.install_handler.sh
- echo "$(date) - Called to labs application to generate and download the installation handler script." >> /root/.install_log
- sh /root/.install_handler.sh
- echo "$(date) - Deployment completed." >> /root/.install_log
EOF
  end

private

  # Create FQDN
  def determine_fqdn
    fqdn = self.safe_name + "." + project.domain
    self.fqdn = fqdn
  end

end
