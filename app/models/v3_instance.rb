class V3Instance < ActiveRecord::Base

  include Instance

  belongs_to :v3_project

  validates :v3_project, presence: true

  # Types should be one of DNS, master, node, router

  def project
    V3Project.find(self.v3_project_id)
  end

  def cloud_init
    p = project
    # Most of this setup will be the same as v2
    ose_version = p.ose_version
    details = p.details

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
- curl #{CONFIG[:URL]}/v3_instances/#{self.id}/callback_script?deployment_id=#{deployment_id} > /root/.install_handler.sh
- echo "$(date) - Called to labs application to generate and download the installation handler script." >> /root/.install_log
- exit_code=255; while [ $exit_code != 0 ]; do echo "$(date) - Attempting to register with RHSM. Previous exit code  $exit_code" >> /root/.install_log; subscription-manager register --force --username=#{CONFIG[:rhsm_username]} --password=#{CONFIG[:rhsm_password]} --name=#{self.safe_name} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Registered via RHSM with username #{CONFIG[:rhsm_username]} and server name #{self.safe_name}." >> /root/.install_log
- exit_code=255; while [ $exit_code == 255 ]; do echo "$(date) - Attempting to attach subscription with pool id #{CONFIG[:rhsm_pool_id]}. Previous exit code  $exit_code" >> /root/.install_log; subscription-manager attach --pool #{CONFIG[:rhsm_pool_id]} &>> /root/.rhsm_output; exit_code=$?; done
- echo "$(date) - Attached pool id #{CONFIG[:rhsm_pool_id]}" >> /root/.install_log
- subscription-manager repos --disable=* &>> /root/.rhsm_output
EOF

    if self.types.include? "master"
      cinit = cinit + <<EOF
- yum localinstall -y https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
- sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
- yum --enablerepo=epel -y install ansible
EOF
    end

    repos = {:server => "rhel-7-server-rpms",
             :extras => "rhel-7-server-extras-rpms",
             :optional => "rhel-7-server-optional-rpms"
            }

    case ose_version
    when "3.0"
      repos[:openshift] = "rhel-7-server-ose-3.0-rpms"
    else
      Rails.logger.error "OSE version not recognized, could not determine subscription manager repository names."
      Rails.logger.error "Instance id: #{self.id}"
      return false
    end

    rhsm_enable_string = repos.map {|repo| "--enable=#{repo} "}

    cinit = cinit + <<EOF
- suscription-manager repos #{rhsm_enable_string}
- echo "$(date) - Removing NetworkManager..." >> /root/.install_log
- yum remove -y NetworkManager*
- echo "$(date) - Installing necessary additional packages..." >> /root/.install_log
- yum install -y sysstat lsof screen wget vim-enhanced mlocate nmap man sos
- yum install -y bind-utils git net-tools iptables-services bridge-utils docker
- echo "$(date) - Completely updating system..." >> /root/.install_log
- yum update -y
- echo "$(date) - Fixing docker options..." >> /root/.install_log
- sed -i '/^OPTIONS/c\OPTIONS="--selinux-enabled --insecure-registry 172.30.0.0/16"' /etc/sysconfig/docker
- echo "$(date) - Downloading docker storage setup files..." >> /root/.install_log
- curl #{CONFIG[:URL]}/v3_instances/#{self.id}/docker_storage_setup_file > /etc/sysconfig/docker-storage-setup
- echo "$(date) - Configuring docker storage..." >> /root/.install_log
- docker-storage-setup
EOF

    # Only ONE master needs installation things
    # Post-installation steps are handled in the '.install_handler.sh' file, which
    #   is generated from 'callback_Script' controller method
    if self.fqdn == details[:master_hostname] && self.internal_ip == details[:master_ip]
      cinit = cinit + <<EOF
- echo "$(date) - Downloading ansible installation configuration files..." >> /root/.install_log
- curl #{CONFIG[:URL]}/v3_instances/#{self.id}/ansible_hosts_file > /etc/ansible/hosts
- echo "$(date) - Acquiring openshift-ansible" >> /root/.install_log
- cd /root/
- git clone https://github.com/openshift/openshift-ansible
- cd openshift-ansible
- git checkout -b 3.x v3.0.0
- cd /root/
- echo "$(date) - Running openshift installation handler..." >> /root/.install_log
- sh /root/.install_handler.sh
- echo "$(date) - Installation procedure finished." >> /root/.install_log
EOF
    else
      cinit = cinit + <<EOF
- echo "$(date) - Installation procedure deferred to a master instance." >> /root/.install_log
EOF
    end
  end

  # TODO placeholder until we make a blank_instance model
  def no_openshift
    false
  end

end
