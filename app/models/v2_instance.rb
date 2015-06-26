class V2Instance < ActiveRecord::Base

  include Instance

  belongs_to :v2_project

  serialize :install_variables

  validates :v2_project, presence: true

  def project
    V2Project.find(self.v2_project_id)
  end

  # Generate cloudinit details 
  def cloud_init(deployment_id)

    ose_version = project.ose_version

    # Establish the base
    cinit=<<EOF
#cloud-config
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
- curl #{CONFIG[:URL]}/v2_instances/#{self.id}/callback_script?deployment_id=#{deployment_id} > /root/.install_handler.sh
- echo "$(date) - Called to labs application to generate and download the installation handler script." >> /root/.install_log
- exit_code=255; while [ $exit_code != 0 ]; do echo "$(date) - Attempting to register with RHSM. Previous exit code  $exit_code" >> /root/.install_log; subscription-manager register --force --username=#{CONFIG[:rhsm_username]} --password=#{CONFIG[:rhsm_password]} --name=#{self.safe_name} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Registered via RHSM with username #{CONFIG[:rhsm_username]} and server name #{self.safe_name}." >> /root/.install_log
- exit_code=255; while [ $exit_code == 255 ]; do echo "$(date) - Attempting to attach subscription with pool id #{CONFIG[:rhsm_pool_id]}. Previous exit code  $exit_code" >> /root/.install_log; subscription-manager attach --pool #{CONFIG[:rhsm_pool_id]} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Attached pool id #{CONFIG[:rhsm_pool_id]}" >> /root/.install_log
- subscription-manager repos --disable=* &>> /root/.rhsm_output
EOF

    # Configure channel names
    case ose_version
    when "1.2"
      repos = {:infra => "rhel-server-ose-1.2-infra-6-rpms",
               :rhc => "rhel-server-ose-1.2-rhc-6-rpms",
               :node => "rhel-server-ose-1.2-node-6-rpms",
               :jbosseap => "rhel-server-ose-1.2-jbosseap-6-rpms"}
    when "2.0", "2.1", "2.2"
      repos = {:infra => "rhel-6-server-ose-#{ose_version}-infra-rpms",
               :rhc => "rhel-6-server-ose-#{ose_version}-rhc-rpms",
               :node => "rhel-6-server-ose-#{ose_version}-node-rpms",
               :jbosseap => "rhel-6-server-ose-#{ose_version}-jbosseap-rpms"}
    else
      Rails.logger.error "OSE version not recognized, could not determine subscription manager repository names."
      Rails.logger.error "Instance id: #{self.id}"
      return false
    end
    repos[:server] = "rhel-6-server-rpms"
    repos[:jbossews] = "jb-ews-2-for-rhel-6-server-rpms"
    repos[:jbosseap_base] = "jb-eap-6-for-rhel-6-server-rpms"
    repos[:rhscl] = "rhel-server-rhscl-6-rpms"

    # Enable repositories and install oo-admin-yum-validator
    if self.types.include?("broker") || self.types.include?("named") || self.types.include?("activemq") || self.types.include?("mongodb")
      cinit = cinit + <<EOF
- subscription-manager repos --enable=#{repos[:server]} --enable=#{repos[:infra]} --enable #{repos[:rhc]} &>> /root/.rhsm_output
- echo "$(date) - Enabled repositories = #{repos[:server]} #{repos[:infra]} #{repos[:rhc]}" >> /root/.install_log
EOF
    end
    
    if self.types.include?("node")
      cinit = cinit + <<EOF
- subscription-manager repos --enable=#{repos[:server]} --enable=#{repos[:node]} --enable=#{repos[:jbossews]} --enable=#{repos[:jbosseap]} --enable=#{repos[:rhscl]} --enable=#{repos[:jbosseap_base]} &>> /root/.rhsm_output
- echo "$(date) - Enabled repositories = #{repos[:server]} #{repos[:node]} #{repos[:jbossews]} #{repos[:jbosseap]} #{repos[:rhscl]} #{repos[:jbosseap_base]}" >> /root/.install_log
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
- yum install sysstat lsof screen wget vim-enhanced mlocate nmap man sos bind-utils -y
- echo "$(date) - System update completed." >> /root/.install_log
- echo "$(date) - Generating installation variables into file /root/.install_variables." >> /root/.install_log
EOF

    if ose_version == "2.0" || ose_version == "1.2"
      # BUGFIX for http://post-office.corp.redhat.com/archives/openshift-sme/2014-October/msg00209.html
      # Also appears to affect 1.2
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
- curl #{CONFIG[:URL]}/ose_files/regenerate_dns.rb > /root/TOOLS/regenerate_dns.rb
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

private

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
    project_details = project.details
    ose_version = project.ose_version
    return nil if project_details.nil?
    variables = { :CONF_DOMAIN => "apps.#{project_details[:domain]}",
                  :CONF_HOSTS_DOMAIN => project_details[:domain],
                  :CONF_NAMED_IP_ADDR => project_details[:named_ip],
                  :CONF_NAMED_HOSTNAME => project_details[:named_hostname],
                  :CONF_DATASTORE_HOSTNAME => project_details[:datastore_replicants].first,
                  :CONF_ACTIVEMQ_HOSTNAME => self.types.include?('activemq') ? self.fqdn :
                                             project_details[:activemq_replicants].first,
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

end
