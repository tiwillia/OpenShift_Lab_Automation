class ProjectsController < ApplicationController

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
      flash[:error] = "Project could not be created."
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
      flash[:error] = "Project could not be updated."
      redirect_to :back
    end
  end

  def show
    @project = Project.find(params[:id])
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

private

  def new_project_params
    params.require(:project).permit!
  end

  def edit_project_params
    params.require(:project).permit!
  end

end
