class AdminController < ApplicationController

  before_filter :is_admin?

  def index
    deployments = Deployment.all 
    @deployments_active = deployments.select {|d| d.in_progress?}.sort_by {|d| d.started_time}
    @deployments_inactive = deployments.select {|d| !d.in_progress?}.sort_by {|d| d.completed_time}.reverse
    @projects = Project.all
    @users = User.all
  end

private

  def is_admin?
    if current_user.nil? || !current_user.admin?
      flash[:error] = "You must be an administrator to perform this action."
      redirect_to :back
    end
  end

end
