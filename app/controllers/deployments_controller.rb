class DeploymentsController < ApplicationController

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

private

  def dep_params
    params.require(:deployment).permit(:message, :instance_id)
  end

end
