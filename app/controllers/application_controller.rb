class ApplicationController < ActionController::Base
  protect_from_forgery

  before_filter :logged_in?

  def logged_in?(redirect = true)
    if cookies[:rh_user]
      username = cookies[:rh_user].split("|").first
      if User.where(:username => username).exists?
        return true
      else
        new_user = User.new(:username => username)
        if new_user.save!
          return true
        else
          flash[:error] = "Could not get user details from RHN."
          return false
        end
      end
    else
      redirect_to "https://redhat.com/wapps/sso/login.html?redirect=#{CONFIG[:URL]}" if redirect
      false
    end
  end 

  def admin?
    current_user.admin?
  end

  def current_user
    if logged_in?(false)
      username = cookies[:rh_user].split("|").first
      if user = User.where(:username => username).first
        return user
      end
    end
    return nil
  end

helper_method :logged_in?, :current_user, :admin?

end
