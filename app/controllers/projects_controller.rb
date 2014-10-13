class ProjectsController < ApplicationController

before_filter :can_edit?, :only => [:uncheck_out, :update, :edit, :start_all, :restart_all, :stop_all, :destroy_on_backend]
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

  def show
    @project = Project.find(params[:id])
    @images = @project.images
    @floating_ips = @project.available_floating_ips
    @flavors = @project.flavors
    @limits = @project.limits
    @instance_id_list = @project.instances.map {|i| i.id}
    @template = Template.new(:project_id => @project.id)
    most_recent_deployment = @project.deployments.last
    if most_recent_deployment and most_recent_deployment.in_progress?
      @deployment = most_recent_deployment
    else
      @deployment = nil
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

  def start_all
    @project = Project.find(params[:id])
    @project.start_all
    flash[:success] = "Project queued to start."
    redirect_to project_path(@project)
  end

  def stop_all
    @project = Project.find(params[:id])
    @project.stop_all
    flash[:success] = "Project stopped."
    redirect_to project_path(@project)
  end
  
  def restart_all
    @project = Project.find(params[:id])
    if @project.stop_all
      @project.start_all
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
