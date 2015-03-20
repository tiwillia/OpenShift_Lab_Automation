namespace :recurring do
  task :init => :environment do
    # Delete any existing scheduled jobs
    Delayed::Job.where('(handler LIKE ?)', '--- !ruby/object:Recurring::%').destroy_all
    # Schedule the recurring jobs
    Recurring::EmailNotifications.schedule!
  end
end
