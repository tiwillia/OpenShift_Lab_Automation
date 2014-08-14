class DeploymentHandler

# This is the handler that controls deployments and their respective threads.
# 'start' creates a single thread that watches for work
#     work must be in the format {action => "start|stop|restart", :project => Project.obj}
# That thread then spins up individual threads as work is added.
 
  def initialize
    @queue = Queue.new
    start
  end

  # Add work to the queue.
  # work should be a hash like: {:action => "stop", :project => Project.obj}
  def enqueue(work)
    dlog "Adding work to queue: #{work.inspect}."
    @queue << work
    if not running?
      dlog "Starting deployment handler thread..."
      start
    end
    dlog("#{@queue.inspect}",:debug)
  end
 
  # Check if the head thread is running 
  def running?
    @thread && @thread.alive?
  end

private
  
  # This is the loop we run through constantly in the background to watch for work.
  def start
    if running?
      dlog("ERROR Tried to start running deployment handler.",:error)
      return false
    end
    @thread = Thread.new do
      loop do
        while @queue.empty? do   
          sleep 10
        end
        work = @queue.pop
        dlog "Work found in queue, starting..."
        Thread.new do
          do_work(work)
          dlog "Work completed."
        end
      end
    end
  end

  # Parse the work and begin the correct action
  def do_work(work)

    project = work[:project]

    case work[:action]

    when "start"
      dlog "Starting deployment #{project.name}"
      begin
        dlog "Started deployment #{project.name}"
        begin_deployment(project)
      rescue => e
        dlog("ERROR could not start deployment #{e.message}", :error)
        dlog("#{e.backtrace}", :error)
      end

    when "stop"
      dlog "Stopping deployment #{project.name}"
      begin
        destroy_deployment(project)
        dlog "Stopped deployment #{project.name}"
      rescue => e
        dlog("ERROR could not stop deployment #{e.message}", :error)
        dlog("#{e.backtrace}", :error)
      end

    when "restart"
      dlog "Restarting deployment #{project.name}"
      begin
        restart_deployment(project)
        dlog "Restarted deployment #{project.name}"
      rescue => e
        dlog("ERROR could not restart deployment #{e.message}", :error)
        dlog("#{e.backtrace}", :error)
      end
     
    else
      dlog("Action not recognized", :error) 
    end
  end


  def begin_deployment(project)
    
    # Order is:
    #   phase1, wait 2 mins, phase 2 + 3, wait 2 mins, phase4
    
    phase1 = []  # named server
    phase2 = []  # All activemq and all but on mongodb
    phase3 = []  # All nodes
    phase4 = []  # The final mongodb and the brokers
 
    dlog "Getting project details..." 
    project_details = project.details
    dlog "Got project details: #{project_details.inspect.to_s}" 

    datastore_instance = ""

    project.instances.each do |inst|
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
    phase1.each {|i| i.start }   
    dlog "Phase one started, waiting 2 minutes..." 
    sleep 120 
    dlog "Phase 2 + 3 begin..." 
    phase2.each {|i| i.start}    
    phase3.each {|i| i.start}    
    dlog "Phase 2 + 3 complete, waiting 2 minutes..." 
    sleep 120
    dlog "Phase 4 begin..." 
    phase4.each {|i| i.start}    
    dlog "Phase 4 complete, waiting for completion..." 

    sleep 30

    broker_instance = project.instances.select {|i| i.types.include?("broker") }.first
    last_node = phase3.last
    all_complete = false 
    complete_instances = []

    # Wait for all instances to complete
    until all_complete do
      project.instances.each do |inst|
        # Close the ssh sesion each time, as the host will likely reboot.
        result = ""
        until result == "DONE"
          ssh = ssh_session(inst)
          result = ssh.exec!("cat /root/.install_tracker").chomp
          ssh.close
          sleep 120 unless result == "DONE"
        end
        complete_instances << inst
        dlog "#{inst.fqdn} complete!"
      end
      if complete_instances.count == project.instances.count
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
    if project.ose_version =~ /2\.[1,2,3]/
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

  def destroy_deployment(project)
    project.instances.each do |inst|
      inst.stop
    end
  end

  def restart_deployment(project)
    destroy_deployment(project)
    begin_deployment(project)
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

end
