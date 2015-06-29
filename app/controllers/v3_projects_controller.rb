class V3ProjectsController < ApplicationController

before_filter :can_edit?, :only => [:deploy_one, :uncheck_out, :update, :edit, :deploy_all, :redeploy_all, :deploy_all, :destroy_on_backend]
before_filter :is_admin?, :only => [:new, :create, :destroy]
before_filter :is_logged_in?, :only => :check_out

  def index
    @projects = Array.new
    Lab.all.sort_by {|l| l.geo}.each do |lab|
      p = V3Project.where(:lab_id => lab.id).sort_by {|p| p.ose_version}
      @projects = @projects + p
    end
    if @projects.empty? && Lab.all.empty?
      redirect_to '/labs/new'
    end
  end

  def new
    @project = V3Project.new
  end

  def create
    @project = V3Project.new(new_project_params)
    if @project.save
      flash[:success] = "Project successfully created."
      redirect_to v3_project_path(@project)
    else
      errors = @project.errors.full_messages
      flash[:error] = errors.join(", ")
      redirect_to :back
    end
  end

  def edit
    @project = V3Project.find(params[:id])
  end

  def update
    @project = V3Project.find(params[:id])
    if @project.update_attributes(edit_project_params)
      flash[:success] = "Project successfully updated."
      redirect_to v3_project_path(@project)
    else
      errors = @project.errors.full_messages
      flash[:error] = errors.join(", ")
      redirect_to :back
    end
  end

  # The project's show page is the main page users will view.
  # We intend to do quite a bit in the controller, so we do as little logic in the view as possible.
  def show
    # Set variables
    @project = V3Project.find(params[:id])
    @images = @project.images
    @floating_ips = @project.available_floating_ips
    @floating_ips = ["NONE AVAILABLE"] if @floating_ips.empty?
    @flavors = @project.flavors
    @limits = @project.limits
    @gear_sizes = CONFIG[:gear_sizes]
    @v3_instance_id_list = @project.v3_instances.map {|i| i.id}
    #@template = Template.new(:v3_project_id => @project.id)
    # TODO above and below
#    @most_recent_deployment = @project.deployments.last
    @most_recent_deployment = nil
    @deployment_status = "unknown"
    case
    when @most_recent_deployment.nil?
      @deployment_status = "never deployed"

    when @most_recent_deployment.in_progress?
      case @most_recent_deployment.action
      when "build", "single_deployment", "redeploy"
        @deployment_status = "build in progress"
      when "tear_down"
        @deployment_status = "tear_down in progress"
      else
        @deployment_status = "unknown"
      end

    when @most_recent_deployment.complete?
      case @most_recent_deployment.action
      when "build", "single_deployment", "redeploy"
        @deployment_status = "complete"
      when "tear_down"
        @deployment_status = "undeployed"
      else
        @deployment_status = "unknown"
      end
    end
  end

  def destroy
    @project = V3Project.find(params[:id])
    if @project.destroy
      flash[:success] = "Project successfully removed."
      redirect_to "/v3_projects"
    else
      flash[:error] = "Project could not be removed."
      redirect_to :back
    end
  end

  def destroy_on_backend
    @project = V3Project.find(params[:id])
    if @project.destroy_all
      flash[:success] = "All backend servers successfully removed."
      redirect_to v3_project_path(@project)
    else
      flash[:error] = "All backend server could not be removed. Contact an administrator now."
      redirect_to :back
    end
  end

  def deploy_all
    @project = V3Project.find(params[:id])
    @project.deploy_all(current_user.id)
    flash[:success] = "Environment deployment has begun. Deployment status will refresh every 10 seconds."
    redirect_to v3_project_path(@project)
  end

  def deploy_one
    @project = V3Project.find(params[:id])
    instance = V3Instance.find(params[:v3_instance_id])
    if @project.deploy_one(instance.id, current_user.id)
      flash[:success] = "#{instance.fqdn} queued for deployment."
    else
      flash[:success] = "#{instance.fqdn} could not be queued for deployment."
    end
    redirect_to v3_project_path(@project)
  end

  def undeploy_all
    @project = V3Project.find(params[:id])
    @project.undeploy_all(current_user.id)
    flash[:success] = "Project queued to undeploy. Deployment status will refresh every 10 seconds."
    redirect_to v3_project_path(@project)
  end
  
  def redeploy_all
    @project = V3Project.find(params[:id])
    if @project.redeploy_all(current_user.id)
      flash[:success] = "Project will be redeployed. Deployment status will refresh every 10 seconds."
      redirect_to v3_project_path(@project)
    else
      flash[:error] = "Project could not be restarted."
      redirect_to v3_project_path(@project)
    end
  end

  def check_out
    logged_in?(true)
    user_id = current_user.id
    @project = V3Project.find(params[:id])
    if @project.checked_out?
      user = User.find(@project.checked_out_by)
      respond_to do |format|
        format.html {
          flash[:error] = "Project is already checked out to #{user.name}"
          redirect_to v3_project_path(@project)
          }
        format.json {
          render :json => {:success => false, :message => "Project is already checked out to #{user.name}"}
        }
      end
    else
      if @project.check_out(user_id)
        respond_to do |format|
          format.html {
            flash[:success] = "Project checked out."
            redirect_to v3_project_path(@project)  
          }
          format.json {
            render :json => {:success => true, :user => current_user.name, :time => DateTime.now.to_s}
          }
        end
      else
        respond_to do |format|
          format.html {
            flash[:error] = "Could not check out project, contact administrator."
            redirect_to v3_project_path(@project)
          }
          format.json {
            render :json => {:success => false, :message => "Could not check out project for some reason."}
          }
        end
      end
    end
  end

  def uncheck_out
    @project = V3Project.find(params[:id])
    if @project.checked_out?
      if @project.uncheck_out
        respond_to do |format|
          format.html {
            flash[:success] = "Project is now available for check out."
            redirect_to v3_project_path(@project)  
          }
          format.json {
            render :json => {:success => true}
          }
        end
      else
        respond_to do |format|
          format.html {
            flash[:error] = "Could not free project, contact administrator."
            redirect_to v3_project_path(@project)
          }
          format.json {
            render :json => {:success => false, :message => "Could not uncheck-out project for some reason."}
          }
        end
      end
    else
      respond_to do |format|
        format.html {
          flash[:error] = "Project is not checked out, cannot free project that is already free."
          redirect_to v3_project_path(@project)
          }
        format.json {
          render :json => {:success => false, :message => "Project is not checked out, can't uncheck-out."}
        }
      end
    end
  end

  # Returns the deployment hash in json
  def check_deployed
    @project = V3Project.find(params[:id])
    deployment_hash = @project.check_all_deployed
    respond_to do |format|
      format.json { render :json => deployment_hash}
    end
  end

  def dns_conf_file
    @project = V3Project.find(params[:id])
    output = @project.generate_dns_file(dns_conf_params[:dns_conf_file])
    respond_to do |format|
      format.text {
        render :text => output, :layout => false
      }
    end
  end

private

  def new_project_params
    params.require(:v3_project).permit!
  end

  def edit_project_params
    params.require(:v3_project).permit!
  end

  def dns_conf_params
    params.require(:v3_project).permit(:id, :dns_conf_file)
  end

  def can_edit?
    @project = V3Project.find(params[:id])
    if @project.checked_out?
      if @project.checked_out_by != current_user(true).id && !current_user(true).admin?
        flash[:error] = "You do not have permissions to make changes to this project."
        redirect_to v3_project_path(@project)  
      end
    elsif !current_user(true).admin?
      flash[:error] = "Check out this project to be able to make changes to it."
      redirect_to v3_project_path(@project)
    end
  end

  def is_admin?
    if !current_user(true).admin?
      flash[:error] = "You must be an administrator to perform this action"
      redirect_to :back
    end
  end

  def is_logged_in?
    if !logged_in?
      redirect_to "https://redhat.com/wapps/sso/login.html?redirect=#{CONFIG[:URL]}"
    end
  end

end
