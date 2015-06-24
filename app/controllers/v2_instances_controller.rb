class V2InstancesController < ApplicationController

before_filter :can_edit?, :except => [:callback_script, :reachable, :new, :create, :check_deployed]
before_filter :is_logged_in?, :only => :console

  def new
    @instance = V2Instance.new
  end

  def create
    pars = new_instance_params
    @instance = V2Instance.new(pars)
    if @instance.save
      flash[:success] = "Instance Successfully created."
      redirect_to :back
    else
      errors = []
      errors = @instance.errors.full_messages
      flash[:error] = errors.join(", ")
      redirect_to :back
    end 
  end

  def edit
    @instance = V2Instance.find(params[:id])
  end

  def update
    pars = edit_instance_params
    @instance = V2Instance.find(params[:id])
    if @instance.update_attributes(pars)
      flash[:success] = "Instance Successfully updated."
      redirect_to :back
    else
      errors = @instance.errors.full_messages
      flash[:error] = errors.join(", ")
      redirect_to :back
    end  
  end
    
  def destroy
    @instance = V2Instance.find(params[:id])
    if @instance.destroy
      flash[:success] = "Instance Successfully removed."
      redirect_to :back
    else
      flash[:error] = "Instance could not be removed."
      redirect_to :back
    end 
  end

  def undeploy
    @instance = V2Instance.find(params[:id])
    if @instance.undeploy
      flash[:success] = "Instance undeployed!"
    else
      flash[:error] = "Instance could not be undeployed."
    end
    redirect_to :back
  end

  def callback_script
    @instance = V2Instance.find(params[:id])
    @deployment = Deployment.find(params[:deployment_id])
    @domain = V2Project.find(@instance.v2_project_id).domain
    render :layout => false
  end

  def reachable
    @instance = V2Instance.find(params[:id])
    reachable, err = @instance.reachable?
    if reachable
      respond_to do |format|
        format.json { render :json => {:reachable => "true"} }
      end
    else
      respond_to do |format|
        format.json { render :json => {:reachable => "false", :error => err} }
      end
    end
  end

  def check_deployed
    @instance = V2Instance.find(params[:id])
    in_progress = @instance.deployment_started
    if in_progress or !@instance.deployed?
      respond_to do |format|
        format.json { render :json => {:deployed => "false", :in_progress => in_progress.to_s} }
      end
    else
      respond_to do |format|
        format.json { render :json => {:deployed => "true", :in_progress => in_progress.to_s} }
      end
    end
  end

  def install_log
    @instance = V2Instance.find(params[:id])
    log_text, error = @instance.install_log
    if log_text
      respond_to do |format|
        format.json { render :json => {:result => "success", :log_text => log_text, :message => ""} }
      end
    else
      respond_to do |format|
        format.json { render :json => {:result => "error", :log_text => "", :message => error } }
      end
    end
  end

  def console
    @instance = V2Instance.find(params[:id])
    result, message = @instance.get_console
    if result
      respond_to do |format|
        format.json { render :json => {:result => "success", :message => message} }
      end
    else
      respond_to do |format|
        format.json { render :json => {:result => "error", :message => message } }
      end
    end
  end

private

  def new_instance_params
    params.require(:instance).permit!
  end

  def edit_instance_params
    params.require(:instance).permit!
  end

  def can_edit?
    @instance = V2Instance.find(params[:id])
    if current_user and (V2Project.find(@instance.v2_project_id).checked_out_by != current_user.id && !current_user.admin)
      flash[:error] = "You do not have permissions to make changes to this instance"
      redirect_to "/v2_projects"
    end
  end

  def is_logged_in?
    if !logged_in?
      redirect_to "https://redhat.com/wapps/sso/login.html?redirect=#{CONFIG[:URL]}"
    end
  end

end
