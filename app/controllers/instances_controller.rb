class InstancesController < ApplicationController

  def new
    @instance = Instance.new
  end

  def create
    pars = new_instance_params
    pars[:types] = pars[:types].split(",")
    @instance = Instance.new(pars)
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
    @instance = Instance.find(params[:id])
  end

  def update
    pars = edit_instance_params
    pars[:types] = pars[:types].split(",")
    @instance = Instance.find(params[:id])
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
    @instance = Instance.find(params[:id])
    if @instance.destroy
      flash[:success] = "Instance Successfully removed."
      redirect_to :back
    else
      flash[:error] = "Instance could not be removed."
      redirect_to :back
    end 
  end

  def start
    @instance = Instance.find(params[:id])
    if @instance.start
      flash[:success] = "Instance started!"
    else
      flash[:error] = "Instance did not start."
    end
    redirect_to :back
  end

  def stop
    @instance = Instance.find(params[:id])
    if @instance.stop
      flash[:success] = "Instance stopped!"
    else
      flash[:error] = "Instance did not stop."
    end
    redirect_to :back
  end

  def restart
    @instance = Instance.find(params[:id])
    if @instance.restart
      flash[:success] = "Instance restarted!"
    else
      flash[:error] = "Instance did not restart."
    end
    redirect_to :back
  end

  def callback_script
    @instance = Instance.find(params[:id])
    @deployment = Deployment.where(:project_id => Project.find(@instance.project_id).id).last
    render :layout => false
  end

  def reachable
    @instance = Instance.find(params[:id])
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

private

  def new_instance_params
    params.require(:instance).permit!
  end

  def edit_instance_params
    params.require(:instance).permit!
  end

end
