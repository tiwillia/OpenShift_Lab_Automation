class LabsController < ApplicationController

  def index
    @labs = Lab.all
  end

  def new
    @lab = Lab.new
  end
    
  def create
    @lab = Lab.new(new_lab_params)
    if @lab.save
      flash[:success] = "Lab #{new_lab_params[:name]} created."
      redirect_to lab_path(@lab)
    else
      flash[:error] = "Lab could not be created."
      redirect_to new_lab_path
    end
  end

  def edit
    @lab = Lab.find(params[:id])
  end
  
  def update
    @lab = Lab.find(params[:id]) 
    if @lab.update_attributes(edit_lab_params)
      flash[:success] = "Lab #{edit_lab_params[:name]} successfully modified."
      redirect_to lab_path(@lab)
    else
      flash[:error] = "Lab could not be modified."
      redirect_to new_lab_path
    end
  end

  def destroy
    @lab = Lab.find(params[:id])
    name = @lab.name
    if @lab.destroy
      flash[:success] = name + " was successfully deleted."
      redirect_to lab_index_path
    else
      flash[:error] = name + " could not be deleted."
      redirect_to :back
    end
  end

  def show
    @lab = Lab.find(params[:id])
  end

private

  def new_lab_params
    params.require(:lab).permit!
  end

  def edit_lab_params
    params.permit!
  end

end
