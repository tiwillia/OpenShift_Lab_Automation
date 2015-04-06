class Notifications < ActionMailer::Base
  include AbstractController::Callbacks
  default from: "no_reply@labs-gssos.itos.redhat.com"

  after_filter :set_inactive_reminder_date, :only => :inactive_reminder

  # Let user know they still have a lab environment checked out.
  def inactive_reminder(user, project)
    @user = user
    @project = project
    email_with_name = "#{@user.name} <#{@user.email}>"
    mail(to: email_with_name, subject: "You have had an OpenShift lab environment checked out for some time meow.")
  end

  private

  # Set the date the email was sent so that we don't send multiple within a single week
  def set_inactive_reminder_date
    @project.update_attributes(:inactive_reminder_sent_at => Date.today)
  end

end
