class V3Project < ActiveRecord::Base

  include Project

  has_many :v3_instances

  def instances
    self.v3_instances
  end

  def find_instance(instance_id)
    V3Instance.find(instance_id)
  end

  def ready?
    q = get_connection("network")

    network = q.networks.select {|n| n.name == self.network}
    if network.empty?
      return false, "Network #{self.network} does not exist on the tenant."
    end

    types = Array.new
    self.v3_instances.each do |inst|
      types << inst.types
    end
    types.flatten!
    duplicates = types.select{|t| types.count(t) > 1}
    # Project should only have one dns instance
    if duplicates.include?("named")
      return false, "Named is a component on multiple instances"
    end

    # For now, projects should only have one router instance
    # TODO support this
    if duplicates.include?("router")
      return false,
        "HA routing is not currently supported. There can only be one instance with the router component."
    end

    # For now, projects should only have one master
    # TODO support this
    if duplicates.include?("master")
      return false, "Multiple masters is not currently supported. There can only be one master instance."
    end

    # Projects MUST have at least 1 node, master, named, router
    types.uniq!
    types.compact!
    if types.sort == ["named", "master", "node", "router"].sort
      true
    else
      return false, "All necessary components are not included: " + types.join(",")
    end

    # Project must not have named on the same system as a master
    named_instance = self.v3_instances.select{|i| i.types.include?("named")}[0]
    unless named_instance.types.include?("master")
      return false, "Named cannot be co-located with master due to the use of SkyDNS"
    end

    # For now (GA limitation), Projects MUST have a node on the same system as master
    master_instances = self.v3_instance.select{|i| i.types.include?("master")}
    master_instance.each do |master|
      return false, "Master instances must also contain a node component" unless master.types.include?("node")
    end
  end

  def details
    # we make assumptions (like that an instance with type named exists)
    # so we need to check for these first
    return nil if not self.ready?

    named_instance = instances.select {|i| i.types.include?("named")}[0]
    named_ip = named_instance.internal_ip
    named_hostname = named_instance.fqdn

    router_instance = instances.select {|i| i.types.include?("router")}[0]
    # Use the external router ip
    router_ip = router_instance.floating_ip
    router_hostname = router_instance.fqdn

    master_instance = instances.select {|i| i.types.include?("master")}[0]
    master_ip = master_instance.internal_ip
    master_hostname = master_instance.fqdn

    node_hostnames = instances.select {|i| i.types.include?("node")}.map {|i| i.fqdn}

    named_entries = instances.map {|i| i.fqdn + ":" + i.floating_ip}
    internal_named_entries = instance.map {|i| i.fqdn + ":" + i.internal_ip}

    return {:domain => self.domain,
            :openshift_username => self.openshift_username,
            :openshift_password => self.openshift_password,
            :named_ip => named_ip,
            :named_hostname => named_hostname,
            :named_entries => named_entries,
            :router_ip => router_ip,
            :router_hostname => router_hostname,
            :master_ip => master_ip,
            :master_hostname => master_hostname,
            :node_hostnames => node_hostnames
           }
  end

  # TODO support v3 templates
  def apply_template
  end

  def generate_dns_file(conf_file=nil)
    project_info = self.details
    domain = project_info[:domain]
    case conf_file
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
  };

  zone "#{domain}" IN {
        type master;
        file "static/#{domain}-global.db";
  };
};
EOF

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
        host, ip = entry.split(":")
        conf += "#{host} A #{ip}\n"
      end

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
        host, ip = entry.split(":")
        conf += "#{host} A #{ip}\n"
      end

    when "wildcard"
      conf=<<EOF
$TTL 30  ; 30 seconds
; 192.168.1.0/24
; 1.168.192.in-addr.arpa.
apps.#{domain}              IN SOA  #{project_info[:named_hostname]}. hostmaster.#{domain}. (
                                2011112942 ; serial
                                60         ; refresh (1 minute)
                                15         ; retry (15 seconds)
                                1800       ; expire (30 minutes)
                                10         ; minimum (10 seconds)
                                )
                        NS      #{project_info[:named_hostname]}.
$ORIGIN #{domain}.
* 300 IN A #{project_info[:router_ip]}
EOF

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
        host, ip = entry.split(":")
        ip_end = ip.split(".")[-1]
        conf += "#{ip_end} IN PTR #{host}.#{domain}.\n"
      end
    else
      Rails.logger.errod "Unknown DNS file requested for v3 instance: #{conf_file}"
    end

  end

end
