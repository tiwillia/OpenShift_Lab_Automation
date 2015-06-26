class Deployment < ActiveRecord::Base

  belongs_to :deployable, polymorphic: true

  after_create :define_instance_vars

  # Easy way to log messages from deployments
  def dlog(message, level = :info)
    date_time = DateTime.now.to_s
    full_message = "[" + date_time + "] (DEPLOYMENT #{self.id}) " + message
    Rails.logger.deployments.send level, full_message
  end

  # Get all log messages from deployment
  def log_messages
    deployment_log = "#{Rails.root}/log/deployments.log"
    if File.exists?(deployment_log)
      messages = String.new
      File.foreach(deployment_log) do |line|
        if line.include?("DEPLOYMENT #{self.id}")
          messages << line
        end
      end
      if messages.empty?
        return "Not log messages found for deployment"
      end
      return messages
    else
      return "No deployment log found"
    end
  end

  def update_status(status_message)
    self.update_attributes(:status => status_message)
    dlog("Updated status: #{status_message}")
  end

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
      if r_val[0] == "interrupt"
        return {:instance_id => nil, :message => r_val[0]}
      else
        return {:instance_id => r_val[0], :message => r_val[1]}
      end
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
        dlog "Queueing deployment #{@project.name}"
        begin
          job = Deployments::BuildJob.new(self.id)
        rescue => e
          dlog("ERROR could not start deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      when "single_deployment"
        dlog "Queueing single deployment for #{@project.name}"
        begin
          job = Deployments::SingleDeploymentJob.new(self.id)
        rescue => e
          dlog("ERROR could not start deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      when "tear_down"
        dlog "Queueing tear down deployment #{@project.name}"
        begin
          job = Deployments::TearDownJob.new(self.id)
        rescue => e
          dlog("ERROR could not undeploy deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      when "redeploy"
        dlog "Queueing redeployment #{@project.name}"
        begin
          job = Deployments::RedeployJob.new(self.id)
        rescue => e
          dlog("ERROR could not restart deployment #{e.message}", :error)
          dlog("#{e.backtrace}", :error)
        end

      else
        dlog("Action not recognized", :error)
      end
      Delayed::Job.enqueue job, :queue => 'deployments'
    rescue => e
      dlog("Could not create job: #{e.message}", :error)
      dlog("#{e.backtrace}", :error)
      self.update_attributes(:started => false)
      return false
    end
    true
  end

  def finish
    self.update_attributes(:complete => true, :completed_time => DateTime.now)
    update_status("Deployment completed")
    dlog("Deployment completed") 
    until self.queue.empty?
      self.pop
    end
  end

  def instance_message(instance_id, message)
    dlog "Got message for instance with id #{instance_id}: \"#{message}\", pushing to deployment queue..."
    if self.queue.nil?
      dlog "Deployment queue has mysteriously become nil, replacing..."  
      $redis.hset("deployment_queue_#{self.id}", nil, nil)
      $redis.hdel("deployment_queue_#{self.id}", nil)
    end
    self.push(instance_id, message)
  end

  def interrupt
    if self.queue.nil?
      dlog "Deployment queue has mysteriously become nil, replacing..."  
      $redis.hset("deployment_queue_#{self.id}", nil, nil)
      $redis.hdel("deployment_queue_#{self.id}", nil)
    end
    $redis.hset("deployment_queue_#{self.id}", "interrupt", "interrupt")
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

  def single_deployment
    update_status("Deployment of a single instance started.")
    @project = self.deployable
    if self.v2_instance_id.nil? && self.v3_instance_id.nil?
      raise "No instance id providied" 
    end
    instance = Instance.find(self.v2_instance_id)

    if instance.deploy(self.id)
      instance.update_attributes(:deployment_started => true, :deployment_completed => false) unless instance.deployment_started && !instance.deployment_completed
      dlog "Started instance #{instance.fqdn} with id #{instance.id} for deployment id #{self.id}"
    else
      dlog("Could not start instance #{instance.fqdn} with id #{instance.id} for deployment id #{self.id}", :error)
      raise "Could not start instance #{instance.fqdn} with id #{instance.id}" 
    end

    complete = false
    time_waited = 0
    update_status("Instance created, waiting for automated deployment to complete.")
    until complete do
      while self.queue.empty? do
        sleep 10
        time_waited += 10
      end
      work = self.pop
      if work[:message] == "interrupt" && work[:v2_instance_id] == nil
        update_status("Deployment interrupted to be stopped.")
        raise "Deployment manually interrupted"
      end
      instance = Instance.find(work[:v2_instance_id])
      message = work[:message]
      case message
      when "success"
        instance.update_attributes(:deployment_completed => true, :deployment_started => false, :reachable => true, :last_checked_reachable => DateTime.now)
        dlog("Instance #{instance.fqdn} completed successfully.")
        complete = true

      when "failure"
        dlog("Instance #{instance.fqdn} failed. Re-deploying", :error)
        instance.undeploy
        update_status("Instance automatic deployment failed, trying again...")
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

  def build_deployment
    case self.deployable_type
    when "V2Project"
      v2_build_deployment
    when "V3Project"
      v3_build_deployment
    else
      raise "Unknown project type provided to deployment"
    end
  end

  def v2_build_deployment
    update_status("Environment deployment started")
    @project = self.deployable

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

    @project.v2_instances.each do |inst|
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

    all_blank = false
    if @project.v2_instances.map {|i| i.types}.flatten == []
      all_blank = true
    end

    update_status("Deployment method determined and configured, deploying instances.")
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
    update_status("Deploying instances, phase 1 complete.")
    unless phase2.empty? && phase3.empty?
      dlog "Phase 2 + 3 begin..." 
      phase2.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
      phase3.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
      dlog "Phase 2 + 3 complete, waiting 2 minutes..." 
      sleep 120
    end
    update_status("Deploying instances, phase 3 complete.")
    dlog "Phase 4 begin..." 
    phase4.each {|i|i.update_attributes(:deployment_started => true, :deployment_completed => false); i.deploy(self.id)}   
    update_status("Deploying instances complete, waiting for automatic OpenShift deployment to complete.")
    dlog "Deployment queue after phase 4: #{self.queue}"
    dlog "Phase 4 complete, waiting for completion..." 

    broker_instance = @project.v2_instances.select {|i| i.types.include?("broker") }.first
    last_node = phase3.last
    all_complete = false 
    complete_instances = []

    # Wait for all instances to complete
    time_waited = 0
    until all_complete do
      while self.queue.empty? do
        sleep 10
        time_waited += 10
        dlog("Waiting for instance callbacks. Time waited: #{time_waited}")
      end
      work = self.pop
      if work[:message] == "interrupt" && work[:v2_instance_id] == nil
        update_status("Deployment interrupted to be stopped.")
        raise "Deployment manually interrupted"
      end
      instance = V2Instance.find(work[:v2_instance_id])
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
      if complete_instances.count == @project.v2_instances.count
        all_complete = true
      end
    end
    update_status("All instances deployed with OpenShift installed, running post deployment operations.")
    dlog("All instances completed. Completed instances: #{complete_instances.map {|i| i.name}}")

    unless all_blank

      # Allow time for the nodes to reboot. They send the all-complete, then reboot. If we try to access them right afterwards, they may be still booting up.
      sleep(30)

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
        rescue => e
          dlog("Unable to ssh to node #{node.fqdn} and restart mcollective, continuing anyway...\n #{e.message}", :error)
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
    end # all blank

    @project.v2_instances.each do |i|
      if i.deployment_completed == false || i.deployment_started == true
        i.update_attributes(:deployment_completed => true, :deployment_started => false)
      end
    end 
    dlog "Deployment complete!"
    self.finish
  end

  def v3_build_deployment
    update_status("Environment deployment started")
    @project = self.deployable

    # Order is:
    #   phase1, wait 2 mins, phase 2 + 3, wait 2 mins, phase4

    phase1 = []  # named server
    phase2 = []  # Everything else
    phase3 = []  # Master where ansible is run

    dlog "Getting project details..."
    project_details = @project.details
    dlog "Got project details: #{project_details.inspect.to_s}"

    @project.v3_instances.each do |inst|
      case
      when inst.internal_ip == project_details[:master_ip]
        phase3 << inst
      when inst.types.include?("named")
        phase1 << inst
      else
        phase2 << inst
      end
    end

    if phase1.empty?
      raise "No named server included or named component is set to be on master instance."
    elsif phase1.length > 1
      raise "Multiple named servers provided"
    end
    if phase3.empty?
      raise "No master server included."
    end

    update_status("Deployment method determined and configured, deploying instances.")
    dlog "Created phases, starting instances..."
    dlog "Phase1: #{phase1}"
    dlog "Phase2: #{phase2}"
    dlog "Phase3: #{phase3}"

    # There should only be one instance in phase 1 and phase 3
    phase1[0].update_attributes(:deployment_started => true, :deployment_completed => false)
    phase1[0].deploy(self.id)
    sleep 120 # necessary to ensure that all instances can resolve in time for deployment
    update_status("Deploying instances, phase 1 complete.")
    phase2.each do |i|
      i.update_attributes(:deployment_started => true, :deployment_completed => false)
      i.deploy(self.id)}
    end
    sleep 120 # TODO is this really necessary?
    update_status("Deploying instances, phase 2 complete.")
    phase3[0].update_attributes(:deployment_started => true, :deployment_completed => false)
    phase3[0].deploy(self.id)
    update_status("Deploying instances, phase 3 complete.")

    dlog "All instances deployed, waiting for all instance to complete..."

    # Wait for all instances to complete
    time_waited = 0
    until all_complete do
      while self.queue.empty? do
        sleep 10
        time_waited += 10
        dlog("Waiting for instance callbacks. Time waited: #{time_waited}")
      end
      work = self.pop
      if work[:message] == "interrupt" && work[:v3_instance_id] == nil
        update_status("Deployment interrupted to be stopped.")
        raise "Deployment manually interrupted"
      end
      instance = V3Instance.find(work[:v3_instance_id])
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
        instance.deploy(self.id).
        instance.update_attributes(:deployment_started => true)
      else
        dlog("Received unprocessable message for project #{@project.name} and instance #{instance.fqdn}: \"#{message}\"",:error)
      end
      if complete_instances.count == @project.v3_instances.count
        all_complete = true
      end
    end
    update_status("All instances deployed with OpenShift installed, running post deployment operations.")

    # Router install
    # Registry install
    # Authenication configuration

    @project.v3_instances.each do |i|
      if i.deployment_completed == false || i.deployment_started == true
        i.update_attributes(:deployment_completed => true, :deployment_started => false)
      end
    end.
    dlog "Deployment complete!"
    self.finish
  end

  def destroy_deployment
    update_status("Un-deployment started, shutting down and destroying instances.")
    @project = self.deployable
    @project.instances.each do |inst|
      inst.undeploy
    end
    update_status("Un-deployment complete. Ensuring backend tenant is ready for a new deployment.")
    self.finish
  end

  def destroy_on_backend
    @project = self.deployable
    @project.destroy_all 
  end

  def rebuild_deployment
    update_status("Re-deployment started, un-deploying environment.")
    destroy_on_backend
    update_status("Cleaning up frontend")
    @project = self.deployable
    @project.instances.each do |inst|
      inst.update_attributes(:deployment_started => false, :deployment_completed => false)
    end
    update_status("Un-deployment complete, waiting for backend to be ready for deployment.")
    build_deployment
  end

private

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

  def define_instance_vars
    @project = self.deployable
  end

end
