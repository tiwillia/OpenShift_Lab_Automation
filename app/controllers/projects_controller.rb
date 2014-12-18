class ProjectsController < ApplicationController

before_filter :can_edit?, :only => [:deploy_one, :uncheck_out, :update, :edit, :deploy_all, :redeploy_all, :deploy_all, :destroy_on_backend]
before_filter :is_admin?, :only => [:new, :create, :destroy]
before_filter :is_logged_in?, :only => :check_out

  def index
    @projects = Project.all
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(new_project_params)
    if @project.save
      flash[:success] = "Project successfully created."
      redirect_to project_path(@project)
    else
      errors = @project.errors.full_messages
      flash[:error] = errors.join(", ")
      redirect_to :back
    end
  end

  def edit
    @project = Project.find(params[:id])
  end

  def update
    @project = Project.find(params[:id])
    if @project.update_attributes(edit_project_params)
      flash[:success] = "Project successfully updated."
      redirect_to project_path(@project)
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
    @project = Project.find(params[:id])
    @images = @project.images
    @floating_ips = @project.available_floating_ips
    @floating_ips = ["NONE AVAILABLE"] if @floating_ips.empty?
    @flavors = @project.flavors
    @limits = @project.limits
    @gear_sizes = CONFIG[:gear_sizes]
    @instance_id_list = @project.instances.map {|i| i.id}
    @template = Template.new(:project_id => @project.id)

    @most_recent_deployment = @project.deployments.last
    @deployment_status = "unknown"
    case
    when @most_recent_deployment.nil?
      @deployment_status = "never deployed"

    when @most_recent_deployment.in_progress?
      case @most_recent_deployment.action
      when "build" || "single_deployment" || "redeploy"
        @deployment_status = "build in progress"
      when "tear_down"
        @deployment_status = "tear_down in progress"
      else
        @deployment_status = "unknown"
      end

    when @most_recent_deployment.complete?
      case @most_recent_deployment.action
      when "build" || "single_deployment" || "redeploy"
        @deployment_status = "complete"
      when "tear_down"
        @deployment_status = "undeployed"
      else
        @deployment_status = "unknown"
      end
    end
  end

  def destroy
    @project = Project.find(params[:id])
    if @project.destroy
      flash[:success] = "Project successfully removed."
      redirect_to project_path(@project)
    else
      flash[:error] = "Project could not be removed."
      redirect_to :back
    end
  end

  def destroy_on_backend
    @project = Project.find(params[:id])
    if @project.destroy_all
      flash[:success] = "All backend servers successfully removed."
      redirect_to project_path(@project)
    else
      flash[:error] = "All backend server could not be removed. Contact an administrator now."
      redirect_to :back
    end
  end

  def deploy_all
    @project = Project.find(params[:id])
    @project.deploy_all
    flash[:success] = "Environment deployment has begun. Deployment status will refresh every 30 seconds."
    redirect_to project_path(@project)
  end

  def deploy_one
    @project = Project.find(params[:id])
    instance = Instance.find(params[:instance_id])
    if @project.deploy_one(instance.id)
      flash[:success] = "#{instance.fqdn} queued for deployment."
    else
      flash[:success] = "#{instance.fqdn} could not be queued for deployment."
    end
    redirect_to project_path(@project)
  end

  def undeploy_all
    @project = Project.find(params[:id])
    @project.undeploy_all
    flash[:success] = "Project queued to undeploy. Deployed will refresh every 30 seconds."
    redirect_to project_path(@project)
  end
  
  def redeploy_all
    @project = Project.find(params[:id])
    if @project.undeploy_all
      @project.deploy_all
      flash[:success] = "Project destroyed and queued to start."
      redirect_to project_path(@project)
    else
      flash[:error] = "Project could not be restarted."
      redirect_to project_path(@project)
    end
  end

  def check_out
    logged_in?(true)
    user_id = current_user.id
    @project = Project.find(params[:id])
    if @project.checked_out?
      user = User.find(@project.checked_out_by)
      flash[:error] = "Project is already checked out to #{user.name}"
      redirect_to project_path(@project)
    else
      if @project.check_out(user_id)
        flash[:success] = "Project checked out."
        redirect_to project_path(@project)  
      else
        flash[:error] = "Could not check out project, contact administrator."
        redirect_to project_path(@project)
      end
    end
  end

  def uncheck_out
    @project = Project.find(params[:id])
    if @project.checked_out?
      if @project.uncheck_out
        flash[:success] = "Project is now available for check out."
        redirect_to project_path(@project)  
      else
        flash[:error] = "Could not free project, contact administrator."
        redirect_to project_path(@project)
      end
    else
      flash[:error] = "Project is not checked out, cannot free project that is already free."
      redirect_to project_path(@project)
    end
  end

private

  def new_project_params
    params.require(:project).permit!
  end

  def edit_project_params
    params.require(:project).permit!
  end

  def can_edit?
    @project = Project.find(params[:id])
    if @project.checked_out?
      if @project.checked_out_by != current_user(true).id && !current_user(true).admin?
        flash[:error] = "You do not have permissions to make changes to this project."
        redirect_to project_path(@project)  
      end
    elsif !current_user(true).admin?
      flash[:error] = "Check out this project to be able to make changes to it."
      redirect_to project_path(@project)
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
