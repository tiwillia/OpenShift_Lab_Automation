class Notifications < ActionMailer::Base
  default from: "no_reply@labs-gssos.itos.redhat.com"

  # Let user know they still have a lab environment checked out.
  def inactive_reminder(user, project)
    @user = user
    @project = project
    email_with_name = "#{@user.name} <#{@user.email}>"
    mail(to: email_with_name, subject: "You have had an OpenShift lab environment checked out for some time meow.")
  end

end
