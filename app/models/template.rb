class Template < ActiveRecord::Base

  before_save :generate_content
  before_save :determine_file_location
  after_save :write_to_disk

  before_destroy :remove_yaml_file

  validates_uniqueness_of :name
  validates_format_of :name, :with => /^[a-zA-Z0-9\ \_\-]+$/i
  validates_presence_of :name, :description, :created_by, :project_id

  serialize :content

  def to_yaml
    self.content.to_yaml
  end

  def generate_content_description
    generate_content if self.content.nil?
    instance_count = self.content["instances"].count
    broker_instances = self.content["instances"].map {|i| i if i["types"].include? "broker"}.compact
    broker_count = broker_instances.count
    datastore_instances = self.content["instances"].map {|i| i if i["types"].include? "datastore"}.compact
    datastore_count = datastore_instances.count
    activemq_instances = self.content["instances"].map {|i| i if i["types"].include? "activemq"}.compact
    activemq_count = activemq_instances.count
    dns_instances = self.content["instances"].map {|i| i if i["types"].include? "named"}.compact
    dns_count = dns_instances.count
    node_instances = self.content["instances"].map {|i| i if i["types"].include? "node"}.compact
    node_count = node_instances.count
    blank_instances = self.content["instances"].map {|i| i if i["no_openshift"] }.compact
    blank_count = blank_instances.count
    node_gear_sizes = self.content["instances"].map{|i| i["gear_size"] if i["types"].include? "node"}.compact.uniq
    content_description = <<EOF
This template contains #{instance_count} instances. There are #{broker_count} brokers, #{datastore_count} datastores, #{activemq_count} activemq servers, #{node_count} nodes, and #{dns_count} named servers. The node gear sizes used are: #{node_gear_sizes.join(',')}.
EOF
    content_description.chomp!
    content_description += " This deployment contains highly available datastores.".chomp if datastore_count >= 3
    content_description += " This deployment contains highly available activemq instances.".chomp if activemq_count >= 2
    content_description += " There are also #{blank_count} instances without an OpenShift type.".chomp if blank_count >= 1
    content_description
  end

private

  def generate_content
    project = Project.find(self.project_id)
    content = {"project_details" => {
      "ose_version" => project.ose_version,
      "mcollective_username" => project.mcollective_username,
      "mcollective_password" => project.mcollective_password,
      "activemq_admin_password" => project.activemq_admin_password,
      "activemq_user_password" => project.activemq_user_password,
      "mongodb_username" => project.mongodb_username,
      "mongodb_password" => project.mongodb_password,
      "mongodb_admin_username" => project.mongodb_admin_username,
      "mongodb_admin_password" => project.mongodb_admin_password,
      "openshift_username" => project.openshift_username,
      "openshift_password" => project.openshift_password,
      "bind_key" => project.bind_key,
      "valid_gear_sizes" => project.valid_gear_sizes
      },
      "instances" => []
    }
    project.instances.each do |inst|
      content["instances"] << {
        "name" => inst.name,
        "types" => inst.types,
        "internal_ip" => inst.internal_ip,
        "root_password" => inst.root_password,
        "gear_size" => inst.gear_size,
        "flavor" => inst.flavor,
        "image" => inst.image,
        "no_openshift" => inst.no_openshift
      }
    end
    self.content = content
    Rails.logger.debug "Content for template generated."
  end
  
  def write_to_disk
    f = File.open(self.file_location, "w")
    f.write(self.to_yaml)
    f.close
    Rails.logger.debug "Content written to disk for template."
  end

  def determine_file_location
    check_template_dir
    file_name = self.name.gsub(" ", "_") 
    self.file_location = "#{CONFIG[:data_dir]}/templates/#{file_name}.yml"
  end

  def check_template_dir
    if not Dir.exists?("#{CONFIG[:data_dir]}/templates")
      Dir.mkdir("#{CONFIG[:data_dir]}/templates/")
    end
  end

  def remove_yaml_file
    File.delete(self.file_location)
  end
  
end
