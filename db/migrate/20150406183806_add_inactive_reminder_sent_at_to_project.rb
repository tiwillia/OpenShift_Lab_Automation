class AddInactiveReminderSentAtToProject < ActiveRecord::Migration
  def change
    add_column :projects, :inactive_reminder_sent_at, :date
  end
end
