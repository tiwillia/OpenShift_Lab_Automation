module Instance
  extend ActiveSupport::Concern

  included do
    before_save :determine_fqdn
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

  def install_log
    if self.reachable?
      begin.
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

end
