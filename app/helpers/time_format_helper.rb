module TimeFormatHelper

  # Returns a date object from a given string
  # This expects the date to be in the format:
  #   mm/dd/yy hh:mm
  def parse_date_s(date_s)
    date = "#{date_s} -0400"
    datetime = DateTime.strptime(date, "%m/%d/%Y %H:%M %z")
    datetime
  end

  def parse_date(date)
    date.strftime("%m/%d/%Y %H:%M")
  end

end
