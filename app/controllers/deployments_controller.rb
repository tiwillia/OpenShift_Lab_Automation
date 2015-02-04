class DeploymentsController < ApplicationController

  before_filter :is_admin?, :only => [:stop,:status]

  def instance_message
    @deployment = Deployment.find(params[:id])
    instance_id = dep_params[:instance_id]
    message = dep_params[:message]
    Rails.logger.debug("Got message from instance with id #{instance_id}: \"#{message}\". Sending to deployment...")
    @deployment.instance_message(instance_id, message)
    respond_to do |format|
      format.json { render :json => {:message => "Success"} }
    end
  end

  def stop
    @deployment = Deployment.find(params[:id])
    if @deployment.interrupt
      respond_to do |format|
        format.json { render :json => {:message => "success"}}
      end
    else
      respond_to do |format|
        format.json { render :json => {:message => "failure"}}
      end
    end
  end

  def status
    @deployment = Deployment.find(params[:id])
    if status = @deployment.status
      respond_to do |format|
        format.json { render :json => {:success => true, :message => status}}
      end
    else
      respond_to do |format|
        format.json { render :json => {:success => false, :message => "failure"}}
      end
    end
  end

  def log_messages
    @deployment = Deployment.find(params[:id])
    if logs = @deployment.log_messages
      respond_to do |format|
        format.json { render :json => {:success => true, :message => logs}}
      end
    else
      respond_to do |format|
        format.json { render :json => {:success => false, :message => "Unable to gather logs."}}
      end
    end
  end

private

  def dep_params
    params.require(:deployment).permit(:message, :instance_id)
  end

  def is_admin?
    if current_user.nil? || !current_user.admin?
      flash[:error] = "You must be an administrator to perform this action."
      redirect_to :back
    end
  end

end
