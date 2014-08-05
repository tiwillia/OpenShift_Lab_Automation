class DeploymentHandler

# This is the handler that controls deployment fors and their respective threads.
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
    Rails.logger.info "DEPLOYMENTS: Adding work to queue: #{work.inspect}."
    @queue << work
    if not running?
      Rails.logger.info "DEPLOYMENTS: Starting deployment handler thread..."
      start
    end
    Rails.logger.debug "DEPLOYMENTS: #{@queue.inspect}"
  end
 
  # Check if the head thread is running 
  def running?
    @thread && @thread.alive?
  end

private
  
  # This is the loop we run through constantly in the background to watch for work.
  def start
    if running?
      Rails.logger.error "DEPLOYMENTS: ERROR Tried to start running deployment handler."
      return false
    end
    @thread = Thread.new do
      loop do
        while @queue.empty? do   
          sleep 10
        end
        work = @queue.pop
        Rails.logger.info "DEPLOYMENTS: Work found in queue, starting..."
        do_work(work)
        Rails.logger.info "DEPLOYMENTS: Work completed."
      end
    end
  end

  # Parse the work and begin the correct action
  def do_work(work)

    project = work[:project]

    case work[:action]

    when "start"
      Rails.logger.info "DEPLOYMENTS: Starting deployment #{project.name}"
      begin
        Rails.logger.info "DEPLOYMENTS: Started deployment #{project.name}"
        begin_deployment(project)
      rescue => e
        Rails.logger.error "DEPLOYMENTS: ERROR could not start deployment #{e.message}"
        Rails.logger.error "DEPLOYMENTS: #{e.backtrace}"
      end

    when "stop"
      Rails.logger.info "DEPLOYMENTS: Stopping deployment #{project.name}"
      begin
        destroy_deployment(project)
        Rails.logger.info "DEPLOYMENTS: Stopped deployment #{project.name}"
      rescue => e
        Rails.logger.error "DEPLOYMENTS: ERROR could not stop deployment #{e.message}"
        Rails.logger.error "DEPLOYMENTS: #{e.backtrace}"
      end

    when "restart"
      Rails.logger.info "DEPLOYMENTS: Restarting deployment #{project.name}"
      begin
        restart_deployment(project)
        Rails.logger.info "DEPLOYMENTS: Restarted deployment #{project.name}"
      rescue => e
        Rails.logger.error "DEPLOYMENTS: ERROR could not restart deployment #{e.message}"
        Rails.logger.error "DEPLOYMENTS: #{e.backtrace}"
      end
     
    else
      Rails.logger.error "DEPLOYMENTS: Action not recognized" 
    end
  end


  def begin_deployment(project)
    
    # Order is:
    #   phase1, wait 2 mins, phase 2 + 3, wait 2 mins, phase4
    
    phase1 = []  # named server
    phase2 = []  # All activemq and all but on mongodb
    phase3 = []  # All nodes
    phase4 = []  # The final mongodb and the brokers
 
    Rails.logger.info "DEPLOYMENTS: Getting project details..." 
    project_details = project.details
    Rails.logger.info "DEPLOYMENTS: Got project details: #{project_details.inspect.to_s}" 

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

    Rails.logger.info "DEPLOYMENTS: Created phases, starting instances..." 
    Rails.logger.info "DEPLOYMENTS: Phase1: #{phase1}" 
    Rails.logger.info "DEPLOYMENTS: Phase2: #{phase2}" 
    Rails.logger.info "DEPLOYMENTS: Phase3: #{phase3}" 
    Rails.logger.info "DEPLOYMENTS: Phase4: #{phase4}" 
    phase1.each {|i| raise "Starting #{i.fqdn} failed" if not project.start_one(i.id) }   
    Rails.logger.info "DEPLOYMENTS: Phase one started, waiting 2 minutes..." 
    sleep 120 
    Rails.logger.info "DEPLOYMENTS: Phase 2 + 3 begin..." 
    phase2.each {|i| project.start_one(i.id)}    
    phase3.each {|i| project.start_one(i.id)}    
    Rails.logger.info "DEPLOYMENTS: Phase 2 + 3 complete, waiting 2 minutes..." 
    sleep 120
    Rails.logger.info "DEPLOYMENTS: Phase 4 begin..." 
    phase4.each {|i| project.start_one(i.id)}    
    Rails.logger.info "DEPLOYMENTS: Phase 4 complete, waiting for completion..." 

    sleep 30

    broker_instance = project.instances.select {|i| i.types.include?("broker") }.first
    last_node = phase3.last
    all_complete = false 
    complete_instances = []

    until all_complete do
      project.instances.each do |inst|
        # Close the ssh sesion each time, as the host will likely reboot.
        until result == "DONE"
          sleep 120
          ssh = ssh_session(inst)
          result = ssh.exec!("cat /root/.install_tracker").chomp
          ssh.close
        end
        complete_instances << inst
        Rails.logger.info "DEPLOYMENTS: #{inst.fqdn} complete!"
      end
      if complete_instances.count == project.instances.count
        all_complete = true
      end
    end

    if defined?(datastore_instance)
      Rails.logger.info "DEPLOYMENTS: Configuring replica set..."
      ssh = ssh_session(datastore_instance)
      ssh.exec!("source /root/.install_variables; sh /root/openshift.sh actions=configure_datastore_add_replicants >> /root/.install_log")
      ssh.close
      Rails.logger.info "DEPLOYMENTS: Datastore replicas configured."
    end

    Rails.logger.info "DEPLOYMENTS: Deployment complete, running post configure..." 
    ssh = ssh_session(broker_instance)
    ssh.exec!("source /root/.install_variables; sh /root/openshift.sh actions=post_deploy >> /root/.install_log")
    Rails.logger.info "DEPLOYMENTS: Deployment complete!"
    ssh.close
  end

  def destroy_deployment(project)
    project.instances.each do |inst|
      project.stop_one(inst.id)
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
        Rails.logger.error "DEPLOYMENTS: SSH failed on attempt ##{tries} with #{e.class}. Retrying..."
        sleep 10
        retry
      else
        Rails.logger.error "DEPLOYMENTS: Could not ssh to #{instance.fqdn} after #{tries.to_s} tries:"
        Rails.logger.error "DEPLOYMENTS: #{e.class} #{e.message}"
        Rails.logger.error "DEPLOYMENTS: #{e.backtrace}"
        raise e
      end
    end
    return ssh
  end

end
