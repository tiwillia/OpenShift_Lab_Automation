module Deployments
class SingleDeploymentJob < Struct.new(:deployment_id)

  def enqueue(job)
    update_status("Job created and queued, waiting for deployment to begin.")
  end

  def perform
    deployment = Deployment.find(deployment_id)
    deployment.single_deployment
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
    update_status("ERROR Job failed - Rolling back deployment")
    deployment = Deployment.find(deployment_id)
    deployment.dlog("Rolling back deployment")
    instance = Instance.find(deployment.v2_instance_id)
    instance.undeploy
    deployment.finish
    deployment.update_status("Deployment failed")
    deployment.dlog("Rollback completed.")
  end

  private

  def update_status(status)
    deployment = Deployment.find(deployment_id)
    deployment.update_attributes(:status => status)
  end

end
end
