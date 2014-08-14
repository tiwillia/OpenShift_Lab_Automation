module TimeFormatHelper

  # Returns a date object from a given string
  # This expects the date to be in the format:
  #   mm/dd/yy hh:mm
  def parse_date_s(date_s)
    datetime = DateTime.strptime(date_s, "%m/%d/%Y %H:%M")
    datetime
  end

  def parse_date(date)
    date_s = date.strftime("%m/%d/%Y %H:%M")
    date_s = date_s + " UTC"
    date_s
  end

end
