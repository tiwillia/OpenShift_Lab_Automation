#!/usr/bin/env oo-ruby

require "/var/www/openshift/broker/config/environment"
Rails.configuration.analytics[:enabled] = false
Mongoid.raise_not_found_error = false
 
class Regenerate
  def self.run
    entries = []
    Application.all.each do |app|
      app.group_instances.each do |group_instance|
        group_instance.gears.each do |gear|
          if app.scalable and not gear.app_dns
            entries |= ["#{gear.uuid}-#{app.domain_namespace}\tCNAME\t#{gear.server_identity}"]
          else
            entries |= ["#{app.name}-#{app.domain_namespace}\tCNAME\t#{gear.server_identity}"]
          end
        end
      end
    end
    entries.each do |entry|
      puts entry
    end
  end
end
 
if __FILE__ == $0
  Regenerate.run
end 
