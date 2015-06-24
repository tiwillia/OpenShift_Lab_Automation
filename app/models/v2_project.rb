class V2Project < ActiveRecord::Base
  require 'base64'

  include Project

  has_many :v2_instances

  validates :name,:domain,:lab,:ose_version, presence: true
 
  def deploy_one(v2_instance_id, user_id)
    deployment = self.deployments.new(:action => "single_deployment", :v2_instance_id => v2_instance_id, :complete => false, :started_by => user_id)
    if deployment.save
      V2Instance.find(v2_instance_id).update_attributes(:deployment_started => true, :deployment_completed => false)
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
    self.v2_instances.each do |i|
      if not i.update_attributes(:deployment_completed => false, :deployment_started => false, :reachable => false)
        Rails.logger.error "Unable to update instance after destroying on backend: #{i.inspect}"
        return false
      end
    end
    return true
  end

  # This checks all instances and returns a hash in the format:
  #   {v2_instance_id => ["deployed"|"in_progress"|"undeployed"]}
  def check_all_deployed
    c = self.get_connection
    servers = c.servers.map {|s| s[:id]}
    deployment_hash = Hash.new
    self.v2_instances.each do |i|
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
    self.v2_instances.each do |i|
      next if i.deployment_completed && !i.deployment_started
      all_deployed = false
      break
    end
    all_deployed
  end

  def none_deployed?
    none_deployed = true
    self.v2_instances.each do |i|
      next if !i.deployment_completed && !i.deployment_started
      none_deployed = false
      break
    end
    none_deployed 
  end

  def apply_template(content, assign_floating_ips=true)
    begin
      raise "Could not destroy all backend instances" unless self.destroy_all
      self.v2_instances.each {|i| i.delete}
      self.update_attributes(content[:project_details])
      floating_ip_list = self.floating_ips if assign_floating_ips
      content["instances"].each do |i|
        new_inst = self.v2_instances.build(i)
        new_inst.v2_project_id = self.id
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
    internal_named_entries = Array.new
    named_ip = ""
    named_hostname = ""
    broker_hostname = ""
    node_hostname = ""

    self.v2_instances.each do |inst|

      if inst.types.include?("named")
        named_instance = inst
        named_ip = named_instance.internal_ip
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
      if inst.internal_ip
        int_named_entry = inst.name + ":" + inst.internal_ip
        internal_named_entries << int_named_entry
      end
    end

    self.v2_instances.first

    return {:named_ip => named_ip,
            :named_hostname => named_hostname,
            :broker_hostname => broker_hostname,
            :node_hostname => node_hostname,
            :named_entries => named_entries,
            :internal_named_entries => internal_named_entries,
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
    self.floating_ips - self.v2_instances.map {|i| i.floating_ip }
  end

  def valid_gear_sizes
    gear_sizes = []
    self.v2_instances.each do |i|
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
    self.v2_instances.each do |inst|
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
    if limits[:max_instances] < self.v2_instances.count
      return false, "There are more #{self.v2_instances.count - limits[:max_instances]} more instances than the project limit of \"#{limits[:max_instances]}\" allows."
    end
    types.uniq!
    types.compact!
    if types.sort == ["named", "broker", "datastore", "activemq", "node"].sort
      true
    else
      return false, "All necessary components are not included: " + types.join(",")
    end
  end

  # conf_file can be one of the following:
  #  named
  #    - /etc/named.conf (default)
  #  static-global
  #    - /var/named/static/<domain>.db-global
  #  static-internal
  #    - /var/named/static/<domain>.db-internal
  #  dynamic-master
  #    - /var/named/dynamic/<apps-domain>.db
  #  dynamic-slave
  #    - /var/named/dynamic/<apps-domain>.db-slave
  #  static-ips
  #    - /var/named/static/<int_ip_without_last_digit> (like 192.168.1)
  #
  #  This method is beyond ugly.
  def generate_dns_file(conf_file=nil)
    project_info = self.details
    domain = project_info[:domain]
    case conf_file
## named.conf
    when nil, "named"
      forwarders = Lab.find(self.lab_id).nameservers.join(";")
      base_file = File.open(Rails.root + "lib/configurations/named.conf_base", 'rb')
      conf = base_file.read
      base_file.close
      conf+=<<EOF
include "apps.#{domain}.key";

acl "openstack" { 192.168.1.0/24; };

view "internal" {
  match-clients { "openstack"; };
  include "/etc/named.rfc1912.zones";
  recursion yes;
  forwarders { #{forwarders}; };

  zone "#{domain}" IN {
        type master;
        file "static/#{domain}-internal.db";
  };

  zone "apps.#{domain}" IN {
          type slave;
          masters { 127.0.0.1; };
          file "dynamic/apps.#{domain}-slave.db";
          allow-notify { #{project_info[:named_ip]}; };
          allow-update-forwarding { "openstack"; };
  };

  zone "1.168.192.in-addr.arpa" IN {
        type master;
        file "static/192.168.1.db";
  };
};

view "global" {
  match-clients { any; };
  include "/etc/named.rfc1912.zones";
  recursion no;

  zone "apps.#{domain}" IN {
          type master;
          file "dynamic/apps.#{domain}.db";
          allow-update { key "apps.#{domain}" ; };
          allow-transfer { 127.0.0.1; #{project_info[:named_ip]}; };
          also-notify { #{project_info[:named_ip]}; };
  };

  zone "#{domain}" IN {
        type master;
        file "static/#{domain}-global.db";
  };
};
EOF

## STATIC GLOBAL
    when "static-global"
      conf=<<EOF
$ORIGIN .
$TTL 60  ; 1 minute
#{domain}              IN SOA  #{project_info[:named_hostname]}. hostmaster.#{domain}. (
                                2011112941 ; serial
                                60         ; refresh (1 minute)
                                15         ; retry (15 seconds)
                                1800       ; expire (30 minutes)
                                10         ; minimum (10 seconds)
                                )
                        NS      #{project_info[:named_hostname]}.
$ORIGIN #{domain}.
apps IN NS #{project_info[:named_hostname]}.

EOF
      project_info[:named_entries].each do |entry|
        host = entry.split(":")[0]
        ip = entry.split(":")[1]
        conf += "#{host} A #{ip}\n"
      end

## STATIC INTERNAL
    when "static-internal"
      conf=<<EOF
$ORIGIN .
$TTL 60  ; 1 minute
#{domain}              IN SOA  #{project_info[:named_hostname]}. hostmaster.#{domain}. (
                                2011112941 ; serial
                                60         ; refresh (1 minute)
                                15         ; retry (15 seconds)
                                1800       ; expire (30 minutes)
                                10         ; minimum (10 seconds)
                                )
                        NS      #{project_info[:named_hostname]}.
$ORIGIN #{domain}.
apps IN NS #{project_info[:named_hostname]}.

EOF
      project_info[:internal_named_entries].each do |entry|
        host = entry.split(":")[0]
        ip = entry.split(":")[1]
        conf += "#{host} A #{ip}\n"
      end

## DYNAMIC
    when "dynamic-master", "dynamic-slave", "dynamic"
      conf=<<EOF
$ORIGIN .
$TTL 10 ; 10 seconds
apps.#{domain}   IN SOA  #{project_info[:named_hostname]}. hostmaster.#{domain}. (
        2012113117 ; serial
        60         ; refresh (1 minute)
        15         ; retry (15 seconds)
        1800       ; expire (30 minutes)
        10         ; minimum (10 seconds)
        )
      NS  #{project_info[:named_hostname]}.
$ORIGIN apps.#{domain}.
$TTL 60 ; 1 minute
EOF
      project_info[:named_entries].each do |entry|
        host = entry.split(":")[0]
        conf += "#{host} CNAME #{host}.#{domain}\n"
      end

## STATIC IPS
    when "static-ips"
      conf=<<EOF
$TTL 60  ; 1 minute
; 192.168.1.0/24
; 1.168.192.in-addr.arpa.
@              IN SOA  #{project_info[:named_hostname]}. hostmaster.#{domain}. (
                                2011112942 ; serial
                                60         ; refresh (1 minute)
                                15         ; retry (15 seconds)
                                1800       ; expire (30 minutes)
                                10         ; minimum (10 seconds)
                                )
                        NS      #{project_info[:named_hostname]}.

EOF
      project_info[:internal_named_entries].each do |entry|
        host = entry.split(":")[0]
        ip_end = entry.split(":")[1].split(".").last
        conf += "#{ip_end} IN PTR #{host}.#{domain}.\n"
      end
    else
      raise "Unrecognized dns configuration file requested."
    end
    conf
  end

  private

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
    self.v2_instances.each do |inst| 
      begin
        inst.destroy
      rescue => e
        Rails.logger.error "Could not remove instance #{inst.fqdn}: #{e.message}"
      end
    end
    Rails.logger.info "All instances removed"
  end

end
