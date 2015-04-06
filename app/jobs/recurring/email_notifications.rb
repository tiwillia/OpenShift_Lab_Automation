module Recurring
  class EmailNotifications
    include Delayed::RecurringJob
    run_every 1.day
    run_at '12:00am'
    timezone 'US/Pacific'
    def perform
      # Check for inactive projects and send emails to users.
      Project.all.each do |project|
        if project.inactive?
          if project.inactive_reminder_sent_at and (Date.today - project.inactive_reminder_sent_at) <= 7
            Rails.logger.info "Not sending reminder email for project #{project.name} because a reminder was sent less than 7 days ago"
          else
            # Send email to user
            user = User.find(project.checked_out_by)
            Notifications.inactive_reminder(user, project).deliver!
          end
        end
      end
    end
  end
end
