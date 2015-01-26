class Deployment < ActiveRecord::Base

  belongs_to :project

  after_create :define_instance_vars

  def queue
    $redis.hgetall("deployment_queue_#{self.id}")
  end

  def push(instance_id, message)
    $redis.hset("deployment_queue_#{self.id}", instance_id, message)
  end

  def pop
    q = self.queue
    if q.length > 0
      r_val = q.first
      $redis.hdel("deployment_queue_#{self.id}", r_val[0])
      return {:instance_id => r_val[0], :message => r_val[1]}
    else
      return false
    end
  end

  def begin
    if running?
      dlog("Attempted to begin deployment with id #{self.id} for project #{@project.id} while already running.",:error)
      return false
    end
    self.update_attributes(:started => true, :started_time => DateTime.now)
    begin
      case self.action

      when "build"
        dlog "Starting deployment #{@project.name}"
        begin
          dlog "Started deployment #{@project.name}"
          build_deployment
        rescue => e
          dlog("ERROR could not start deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      when "single_deployment"
        dlog "Starting single deployment for #{@project.name}"
        begin
          dlog "Started deployment #{@project.name}"
          single_deployment
        rescue => e
          dlog("ERROR could not start deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      when "tear_down"
        dlog "Undeploying deployment #{@project.name}"
        begin
          destroy_deployment
          dlog "Undeploying deployment #{@project.name}"
        rescue => e
          dlog("ERROR could not undeploy deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      # NOT USED YET
      when "destroy_all"
        dlog "Destroying all instances on the backend for project #{@project.name}"
        begin
          destroy_on_backend
          dlog "Destroyed all isntances on the backend for project #{@project.name}"
        rescue => e
          dlog("ERROR could not destroy all instances on the backend #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      when "redeploy"
        dlog "Restarting deployment #{@project.name}"
        begin
          rebuild_deployment
          dlog "Restarted deployment #{@project.name}"
        rescue => e
          dlog("ERROR could not restart deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      else
        dlog("Action not recognized", :error)
      end
    rescue => e
      dlog("CRITICAL ERROR | Thread failed with: #{e.message}", :error)
      dlog("#{e.backtrace}", :error)
      self.update_attributes(:started => false)
      return false
    end
    true
  end

  def finish
    self.update_attributes(:complete => true, :completed_time => DateTime.now) 
    until self.queue.empty?
      self.pop
    end
  end

  def instance_message(instance_id, message)
    dlog "Got message for #{Instance.find(instance_id).fqdn}: \"#{message}\", pushing to deployment queue..."
    if self.queue.nil?
      dlog "Deployment queue has mysteriously become nil, replacing..."  
      $redis.hset("deployment_queue_#{self.id}", nil, nil)
      $redis.hdel("deployment_queue_#{self.id}", nil)
    end
    self.push(instance_id, message)
  end

  def in_progress?
    if self.started && !self.complete
      true
    else
      false
    end
  end

  def complete?
    self.complete
  end

  def running?
    self.in_progress?
  end

private
  
  def single_deployment
    @project = Project.find(self.project_id)
    raise "No instance id providied" if self.instance_id.nil?
    instance = Instance.find(self.instance_id)

    if instance.deploy(self.id)
      instance.update_attributes(:deployment_started => true, :deployment_completed => false) unless instance.deployment_started && !instance.deployment_completed
      dlog "Started instance #{instance.fqdn} with id #{instance.id} for deployment id #{self.id}"
    else
      dlog("Could not start instance #{instance.fqdn} with id #{instance.id} for deployment id #{self.id}", :error)
      return false
    end

    complete = false
    time_waited = 0
    until complete do
      while self.queue.empty? do
        sleep 10
        time_waited += 10
      end
      work = self.pop
      instance = Instance.find(work[:instance_id])
      message = work[:message]
      case message
      when "success"
        instance.update_attributes(:deployment_completed => true, :deployment_started => false, :reachable => true, :last_checked_reachable => DateTime.now)
        dlog("Instance #{instance.fqdn} completed successfully.")
        complete = true

      when "failure"
        dlog("Instance #{instance.fqdn} failed. Re-deploying", :error)
        instance.undeploy
        sleep 5
        instance.deploy(self.id)
        instance.update_attributes(:deployment_started => true, :deployment_completed => false)
        
      else
        dlog("Received unprocessable message for project #{@project.name} and instance #{instance.fqdn}: \"#{message}\"",:error)
      end
    end
    dlog "Deployment complete!"
    self.finish
  end
  handle_asynchronously :single_deployment, :queue => "deployments", :run_at => Proc.new { DateTime.now }

  def build_deployment
    @project = Project.find(self.project_id)

    # Order is:
    #   phase1, wait 2 mins, phase 2 + 3, wait 2 mins, phase4
    
    phase1 = []  # named server
    phase2 = []  # All activemq and all but one mongodb
    phase3 = []  # All nodes
    phase4 = []  # The final mongodb and the brokers
 
    dlog "Getting project details..." 
    project_details = @project.details
    dlog "Got project details: #{project_details.inspect.to_s}" 

    datastore_instance = ""

    @project.instances.each do |inst|
      case 
      when inst.types.include?("named")
        phase1 << inst
      when inst.types.include?("activemq") || inst.types.include?("datastore")
        if project_details[:datastore_replicants].count > 1 && project_details[:datastore_replicants].first == inst.fqdn
          phase4 << inst  # If there are mongodb replicants, the first should be the last to get started
          datastore_instance = inst
        else
          phase2 << inst
        end
      when inst.types.include?("activemq")
        phase2 << inst
      when inst.types.include?("node")
        phase3 << inst
      else
        phase4 << inst
      end
    end

    dlog "Created phases, starting instances..." 
    dlog "Phase1: #{phase1}" 
    dlog "Phase2: #{phase2}" 
    dlog "Phase3: #{phase3}" 
    dlog "Phase4: #{phase4}" 
    unless phase1.empty?
      phase1.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
      dlog "Phase one started, waiting 2 minutes..." 
      sleep 120 
    end
    unless phase2.empty? && phase3.empty?
      dlog "Phase 2 + 3 begin..." 
      phase2.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
      phase3.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
      dlog "Phase 2 + 3 complete, waiting 2 minutes..." 
      sleep 120
    end
    dlog "Phase 4 begin..." 
    phase4.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
    dlog "Deployment queue after phase 4: #{self.queue}"
    dlog "Phase 4 complete, waiting for completion..." 

    broker_instance = @project.instances.select {|i| i.types.include?("broker") }.first
    last_node = phase3.last
    all_complete = false 
    complete_instances = []
    @project.instances.where(:no_openshift => true).each {|i| complete_instances << i}

    # Wait for all instances to complete
    time_waited = 0
    until all_complete do
      while self.queue.empty? do
        sleep 10
        time_waited += 10
        dlog("Waiting for instance callbacks. Time waited: #{time_waited}")
      end
      work = self.pop
      instance = Instance.find(work[:instance_id])
      message = work[:message]
      case message
      when "success"
        complete_instances << instance
        instance.update_attributes(:deployment_completed => true, :deployment_started => false, :reachable => true, :last_checked_reachable => DateTime.now)
        dlog("Instance #{instance.fqdn} completed successfully.")
        dlog("Complete instance count: #{complete_instances.count}")
      when "failure"
        dlog("Instance #{instance.fqdn} failed. Re-deploying", :error)
        instance.undeploy
        sleep 5
        instance.deploy(self.id) 
        instance.update_attributes(:deployment_started => true)
      else
        dlog("Received unprocessable message for project #{@project.name} and instance #{instance.fqdn}: \"#{message}\"",:error)
      end
      if complete_instances.count == @project.instances.count
        all_complete = true
      end
    end 
    dlog("All instances completed. Completed instances: #{complete_instances.map {|i| i.name}}")

    # Datastore replicant configuration
    if datastore_instance.class == Instance
      dlog "Configuring replica set..."
      replicants_complete = false
      tries = 0
      until replicants_complete || tries > 5 do
        tries += 1
        ssh = ssh_session(datastore_instance)
        ssh.exec!("source /root/.install_variables; sh /root/openshift.sh actions=configure_datastore_add_replicants >> /root/.install_log")
        exit_code = ssh.exec!("echo $?").chomp
        ssh.close
        if exit_code == "0"
          replicants_complete = true
        else
          dlog("Replica set configuration failed, trying again...", :error)
          sleep 30
        end
      end
      if replicants_complete
        dlog "Datastore replicas configured."
      else
        dlog("Could not configure datstore after #{tries} tries. Giving up.", :error)
      end
    end

    # Restart mcollective on nodes to ensure availablity
    phase3.each do |node|
      dlog("Restarting mcollective on node #{node.fqdn} with id #{node.id}")
      begin
        ssh_session(node)
        ssh.exec!("service ruby193-mcollective restart")
      rescue
        dlog("Unable to ssh to node #{node.fqdn} and restart mcollective, continuing anyway...", :error)
      end
    end

    # Post deployment script
    if @project.ose_version =~ /2\.[1,2,3]/
      dlog "Running post deploy..."
      post_deploy_complete = false
      tries = 0
      until post_deploy_complete || tries > 5 do
        tries += 1
        ssh = ssh_session(broker_instance)
        ssh.exec!("source /root/.install_variables; sh /root/openshift.sh actions=post_deploy >> /root/.install_log")
        exit_code = ssh.exec!("echo $?").chomp
        ssh.close
        if exit_code == "0"
          post_deploy_complete = true
        else
          dlog("Post deployment failed, trying again...", :error)
          sleep 30
        end
      end
      if post_deploy_complete
        dlog "Post deployment complete."
      else
        dlog("Could not post deploy after #{tries} tries. Giving up.", :error)
      end
    end
   
    @project.instances.each do |i|
      if i.deployment_completed == false || i.deployment_started == true
        i.update_attributes(:deployment_completed => true, :deployment_started => false)
      end
    end 
    dlog "Deployment complete!"
    self.finish
  end
  handle_asynchronously :build_deployment, :queue => "deployments", :run_at => Proc.new { DateTime.now }
  
  def destroy_deployment
    @project = Project.find(self.project_id)
    @project.instances.each do |inst|
      inst.undeploy
    end
    # destroy_on_backend is not necessary at all, but we do it to avoid confusion for users who don't realize that
    #   a server not created by the project might exist on the openstack backend.
    destroy_on_backend
    self.finish
  end
  handle_asynchronously :destroy_deployment, :queue => "deployments", :run_at => Proc.new { DateTime.now }

  def destroy_on_backend
    @project = Project.find(self.project_id)
    @project.destroy_all 
  end

  def rebuild_deployment
    destroy_on_backend
    sleep 20 # Wait for slow openstack servers
    build_deployment
    self.finish
  end
  handle_asynchronously :rebuild_deployment, :queue => "deployments", :run_at => Proc.new { DateTime.now }

  def ssh_session(instance)
    ip = instance.floating_ip
    passwd = instance.root_password
    tries = 0
    begin
      ssh = Net::SSH.start(ip, 'root', :password => passwd, :paranoid => false)
    rescue => e
      tries += 1
      if tries < 6
        dlog("SSH to #{instance.fqdn} failed on attempt ##{tries} with #{e.class}. Retrying...", :error)
        sleep 10
        retry
      else
        dlog("Could not ssh to #{instance.fqdn} after #{tries.to_s} tries:", :error)
        dlog("#{e.class} #{e.message}", :error)
        dlog("#{e.backtrace}", :error)
        raise e
      end
    end
    return ssh
  end

  # Easy way to log from deployments
  def dlog(message, level = :info)
    date_time = DateTime.now.to_s
    full_message = "[" + date_time + "] (DEPLOYMENT #{self.id}) " + message
    Rails.logger.send level, full_message
  end

  def define_instance_vars
    @project = Project.find(self.project_id)
  end

end
