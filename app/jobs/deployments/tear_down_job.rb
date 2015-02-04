module Deployments
class TearDownJob < Struct.new(:deployment_id)

  def enqueue(job)
    update_status("Job created and queued, waiting for deployment to begin.")
  end

  def perform
    deployment = Deployment.find(deployment_id)
    deployment.destroy_deployment
  end

  def success(job)
    deployment = Deployment.find(deployment_id)
    deployment.finish
  end

  def error(job, exception)
    update_status("ERROR #{exception.message}")
    deployment = Deployment.find(deployment_id)
    deployment.dlog("ERROR in deployment: #{exception.message}")
    deployment.dlog(exception.backtrace)
  end

  def failure(job)
    # Roll back the job
    # Can't really rollback any already deleted instances
    deployment = Deployment.find(deployment_id)
    deployment.dlog("Deployment failed - Can't roll back tear down deployment")
    update_status("Deployment failed")
  end

  private

  def update_status(status)
    deployment = Deployment.find(deployment_id)
    deployment.update_attributes(:status => status)
  end

end
end
