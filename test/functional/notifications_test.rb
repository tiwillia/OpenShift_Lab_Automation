require 'test_helper'

class NotificationsTest < ActionMailer::TestCase
  test "inactive_reminder" do
    mail = Notifications.inactive_reminder
    assert_equal "Inactive reminder", mail.subject
    assert_equal ["to@example.org"], mail.to
    assert_equal ["from@example.com"], mail.from
    assert_match "Hi", mail.body.encoded
  end

end
