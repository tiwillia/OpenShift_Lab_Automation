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
      Rails.logger.info "DEPLOYMENTS: Starting deployment for #{project.name}"
      begin
        Rails.logger.info "DEPLOYMENTS: Started deployment for #{project.name}"
        begin_deployment(project)
      rescue => e
        Rails.logger.error "DEPLOYMENTS: ERROR could not start deployment for #{e.message}"
        Rails.logger.error "DEPLOYMENTS: #{e.backtrace}"
      end

    when "stop"
      Rails.logger.info "DEPLOYMENTS: Stopping deployment for #{project.name}"
      destroy_deployment(project)
      begin
        Rails.logger.info "DEPLOYMENTS: Stopped deployment for #{project.name}"
      rescue => e
        Rails.logger.error "DEPLOYMENTS: ERROR could not stop deployment for #{e.message}"
        Rails.logger.error "DEPLOYMENTS: #{e.backtrace}"
      end

    when "restart"
      Rails.logger.info "DEPLOYMENTS: Restarting deployment for #{project.name}"
      restart_deployment(project)
      begin
        Rails.logger.info "DEPLOYMENTS: Restarted deployment for #{project.name}"
      rescue => e
        Rails.logger.error "DEPLOYMENTS: ERROR could not restart deployment for #{e.message}"
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

    project.instances.each do |inst|
      case 
      when inst.types.include?("named")
        phase1 << inst
      when inst.types.include?("activemq") || inst.types.include?("datastore")
        if project_details[:datastore_replicants].count > 1 && project_details[:datastore_replicants].first == inst.fqdn
          phase4 << inst  # If there are mongodb replicants, the first should be the last to get started
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
    Rails.logger.info "DEPLOYMENTS: Phase 2 + 3 complete, waiting 5 minutes..." 
    sleep 300
    Rails.logger.info "DEPLOYMENTS: Phase 4 begin..." 
    phase4.each {|i| project.start_one(i.id)}    
    Rails.logger.info "DEPLOYMENTS: Phase 4 complete, waiting for completion..." 

    sleep 30

    broker_instance = project.instances.select {|i| i.types.include?("broker") }.first
    last_node_complete = false
    last_node = phase3.last
    until last_node_complete == true do
      # Close the ssh sesion each time, as the host will likely reboot.
      ssh = Net::SSH.start(last_node.floating_ip, 'root', :password => last_node.root_password, :paranoid => false)
      result = ssh.exec!("cat /root/.install_tracker").chomp
      if result == "DONE"
        last_node_complete = true
      end
      Rails.logger.info "DEPLOYMENTS: Waiting for deployment completion..." 
      ssh.close
      sleep 120
    end
   
    Rails.logger.info "DEPLOYMENTS: Deployment complete, running post configure..." 
    ssh = Net::SSH.start(broker_instance.floating_ip, 'root', :password => broker_instance.root_password, :paranoid => false)
    ssh.exec!("source /root/.install_variables; sh /root/openshift.sh actions=post_deploy")
    Rails.logger.info "DEPLOYMENTS: Deployment complete!"
    ssh.close

  end

end
