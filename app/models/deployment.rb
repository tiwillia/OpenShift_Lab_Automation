class Deployment < ActiveRecord::Base

  belongs_to :project
  cattr_accessor :thread, :queue

  # Essentially, I need to move everything in the deployment handler to here. In begin, I need to
  # start a new thread to do the deployment. But then I need to be able to watch a queue for 
  # when the instances come back. That shouldn't be too hard, just use the instance_message method to 
  # send it to a queue, which would be... an instance variable? Or perhaps a database entry?

  after_initialize :define_instance_vars

  def begin
    if running?
      dlog("Attempted to begin deployment with id #{self.id} for project #{@project.id} while already running.",:error)
      return false
    end
    self.thread = Thread.new {
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

      when "tear_down"
        dlog "Stopping deployment #{@project.name}"
        begin
          destroy_deployment
          dlog "Stopped deployment #{@project.name}"
        rescue => e
          dlog("ERROR could not stop deployment #{e.message}", :error)
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
    }
    if running?
      self.update_attributes(:started => true, :started_time => DateTime.now)
      return true
    else
      return false
    end
  end

  def instance_message(instance_id, message)
    Rails.logger.debug "Got message for #{Instance.find(instance_id).fqdn}: \"#{message}\", pushing to deployment queue..."
    self.queue.push({:instance_id => instance_id, :message => message})
  end

  def in_progress?
    if self.started && !self.complete
      true
    else
      false
    end
  end

  def running?
    self.thread && self.thread.alive?
  end

private
  
  def build_deployment
    # Order is:
    #   phase1, wait 2 mins, phase 2 + 3, wait 2 mins, phase4
    
    phase1 = []  # named server
    phase2 = []  # All activemq and all but on mongodb
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
    phase1.each {|i| i.start; i.update_attributes(:deployment_started => true)}   
    dlog "Phase one started, waiting 2 minutes..." 
    sleep 120 
    dlog "Phase 2 + 3 begin..." 
    phase2.each {|i| i.start; i.update_attributes(:deployment_started => true)}    
    phase3.each {|i| i.start; i.update_attributes(:deployment_started => true)}    
    dlog "Phase 2 + 3 complete, waiting 2 minutes..." 
    sleep 120
    dlog "Phase 4 begin..." 
    phase4.each {|i| i.start; i.update_attributes(:deployment_started => true)}    
    dlog "Phase 4 complete, waiting for completion..." 

    sleep 30

    broker_instance = @project.instances.select {|i| i.types.include?("broker") }.first
    last_node = phase3.last
    all_complete = false 
    complete_instances = []

    # Wait for all instances to complete
    until all_complete do
      while self.queue.empty? do
        dlog("Queue empty, waiting 10 secs...", :debug)
        sleep 10
      end
      work = self.queue.pop
      instance = Instance.find(work[:instance_id])
      message = work[:message]
      case message
      when "success"
        complete_instances << instance
        instance.update_attributes(:deployment_completed => true, :deployment_started => false, :reachable => true)
        dlog("Instance #{instance.fqdn} completed successfully.")
      when "failed"
        dlog("Instance #{instance.fqdn} failed. Re-deploying", :error)
        instance.stop
        sleep 5
        instance.start 
      else
        dlog("Received unprocessable message for project #{@project.name} and instance #{instance.fqdn}: \"#{message}\"",:error)
      end
      if complete_instances.count == @project.instances.count
        all_complete = true
      end
    end 

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
    
    dlog "Deployment complete!"
    
  end
  
  def destroy_deployment
    @project.instances.each do |inst|
      inst.stop
    end
  end

  def rebuild_deployment
    destroy_deployment
    sleep 20 # Wait for slow openstack servers
    begin_deployment
  end

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
    full_message = "[" + date_time + "] (DEPLOYMENT) " + message
    Rails.logger.send level, full_message
  end

  def define_instance_vars
    self.thread = nil
    self.queue = Queue.new
    @project = Project.find(self.project_id)
  end

end
