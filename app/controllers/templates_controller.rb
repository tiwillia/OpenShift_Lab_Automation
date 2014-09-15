class TemplatesController < ApplicationController

  def create
    @template = Template.new(template_params)
    if @template.save
      respond_to do |format|
        format.json { render :json => {:created => "true"} } 
      end
    else
      respond_to do |format|
        format.json { render :json => {:created => "false"} }
      end
    end
  end

  def index
    @users_templates = Template.where(:created_by => current_user.id) unless not logged_in?
    @templates = Template.all
    @templates = @templates - @users_templates if defined? @users_templates
  end

  def show
    @template = Template.find(params[:id])
  end

  def destroy
    @template = Template.find(params[:id])
    if @template.delete
      flash[:success] = "Template deleted."
    else
      flash[:error] = "Template could not be deleted."
    end
    redirect_to "/templates"
  end

  def apply
    @template = Template.find(params[:id])
    project = Project.find(template_params[:project_id])
    if project.apply_template(@template.content)
      respond_to do |format|
        format.json { render :json => {:applied => "true", :project_id => project.id} }
      end
    else
      respond_to do |format|
        format.json { render :json => {:applied => "false", :project_id => project.id} }
      end
    end
     
  end

private

  def template_params
    params.require(:template).permit(:name, :description, :project_id, :created_by)
  end

end
