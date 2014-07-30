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
      flash[:error] = "Instance could not be created."
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
      flash[:error] = "Instance could not be updated."
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

private

  def new_instance_params
    params.require(:instance).permit!
  end

  def edit_instance_params
    params.require(:instance).permit!
  end

end
