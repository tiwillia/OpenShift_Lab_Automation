class V3Instance < ActiveRecord::Base
  #attr_accessible :deployment_completed, :deployment_started, :flavor, :floating_ip, :fqdn, :image, :internal_ip, :last_checked_reachable, :name, :reachable, :root_password, :uuid, :v3_project_id

  include Instance

  belongs_to :v3_project

  def project
    V3Project.find(self.v3_project_id)
  end

  def deployed?
  end

  def install_log
  end

  def get_console
  end

  def deploy(deployment_id)
  end

  def undeploy
  end

  def cloud_init
  end

end
