Delayed::Worker.sleep_delay = 30
Delayed::Worker.delay_jobs = !Rails.env.test?
Delayed::Worker.max_attempts = 1
Delayed::Worker.max_run_time = 4.hours
Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', 'delayed_job.log'))
#Delayed::Job.destroy_failed_jobs = false
