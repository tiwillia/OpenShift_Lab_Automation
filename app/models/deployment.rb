class Deployment < ActiveRecord::Base

  belongs_to :project

  # Essentially, I need to move everything in the deployment handler to here. In begin, I need to
  # start a new thread to do the deployment. But then I need to be able to watch a queue for 
  # when the instances come back. That shouldn't be too hard, just use the instance_message method to 
  # send it to a queue, which would be... an instance variable? Or perhaps a database entry?

  after_create :define_instance_vars

  def begin
    if running?
      dlog("Attempted to begin deployment with id #{self.id} for project #{@project.id} while already running.",:error)
      return false
    end
    DEPLOYMENT_THREADS[self.id] = Thread.new {
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

      when "tear_down"
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
      self.finish
  
    }
    if running?
      self.update_attributes(:started => true, :started_time => DateTime.now)
      return true
    else
      return false
    end
  end

  def finish
    self.update_attributes(:complete => true, :completed_time => DateTime.now) 
  end

  def instance_message(instance_id, message)
    dlog "Got message for #{Instance.find(instance_id).fqdn}: \"#{message}\", pushing to deployment queue..."
    DEPLOYMENT_QUEUES[self.id].push({:instance_id => instance_id, :message => message})
  end

  def in_progress?
    if self.started && !self.complete
      true
    else
      false
    end
  end

  def running?
    DEPLOYMENT_THREADS[self.id] && DEPLOYMENT_THREADS[self.id].alive?
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
    phase1.each {|i| i.start; i.update_attributes(:deployment_started => true, :deployment_completed => false)}   
    dlog "Phase one started, waiting 2 minutes..." 
    sleep 120 
    dlog "Phase 2 + 3 begin..." 
    phase2.each {|i| i.start; i.update_attributes(:deployment_started => true, :deployment_completed => false)}    
    phase3.each {|i| i.start; i.update_attributes(:deployment_started => true, :deployment_completed => false)}    
    dlog "Phase 2 + 3 complete, waiting 2 minutes..." 
    sleep 120
    dlog "Deployment queue before phase 4: #{DEPLOYMENT_QUEUES[self.id].inspect}"
    dlog "Phase 4 begin..." 
    phase4.each {|i| i.start; i.update_attributes(:deployment_started => true, :deployment_completed => false)}    
    dlog "Deployment queue after phase 4: #{DEPLOYMENT_QUEUES[self.id].inspect}"
    dlog "Phase 4 complete, waiting for completion..." 

    broker_instance = @project.instances.select {|i| i.types.include?("broker") }.first
    last_node = phase3.last
    all_complete = false 
    complete_instances = []
    @project.instances.where(:no_openshift => true).each {|i| complete_instances << i}

    # Wait for all instances to complete
    time_waited = 0
    until all_complete do
      while DEPLOYMENT_QUEUES[self.id].empty? do
        time_waited += 10
        dlog("Queue empty, waiting 10 secs. Waited #{time_waited.to_s} seconds so far.", :debug)
        sleep 10
      end
      work = DEPLOYMENT_QUEUES[self.id].pop
      instance = Instance.find(work[:instance_id])
      message = work[:message]
      case message
      when "success"
        complete_instances << instance
        instance.update_attributes(:deployment_completed => true, :deployment_started => false, :reachable => true, :last_checked_reachable => DateTime.now)
        dlog("Instance #{instance.fqdn} completed successfully.")
      when "failure"
        dlog("Instance #{instance.fqdn} failed. Re-deploying", :error)
        instance.stop
        sleep 5
        instance.start 
        instance.update_attributes(:deployment_started => true)
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
   
    @project.instances.each do |i|
      if i.deployment_complete == false || i.deployment_started == true
        i.update_attributes(:deployment_completed => true, :deployment_started => false)
      end
    end 
    dlog "Deployment complete!"
    
  end
  
  def destroy_deployment
    @project.instances.each do |inst|
      inst.stop
    end
  end

  def destroy_on_backend
    @project.destroy_all 
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
    DEPLOYMENT_THREADS[self.id] = nil
    DEPLOYMENT_QUEUES[self.id] = Queue.new
    @project = Project.find(self.project_id)
  end

end
