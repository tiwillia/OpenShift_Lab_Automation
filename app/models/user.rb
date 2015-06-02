class User < ActiveRecord::Base
#  attr_accessible :admin, :email, :first_name, :hashed_password, :last_name, :name, :salt

  require 'net/http'
  require 'uri'

  validates :first_name, :last_name, :username, :email, presence: true
  validates :email, uniqueness: true
  validates :email, format: /^([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})$/i

  before_validation :get_user_details
  before_create :check_admin


  def admin?
    self.admin
  end

  def name
    self.first_name + " " + self.last_name
  end

private

  def check_admin
    if self.email == CONFIG[:admin_email]
      self.admin = true
    end
  end

  def get_user_details
    response = unified_get(self.username) 
    details = response.body
    self.first_name = details["firstname"]
    self.last_name = details["lastname"]
    self.email = details["email"]
  end

  def unified_get(username)
    url = "https://unified.gsslab.rdu2.redhat.com/sfdc_user?sso_username=#{username}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    response.body = JSON.parse(response.body)
    response
  end

end
