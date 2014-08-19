class ApplicationController < ActionController::Base
  protect_from_forgery

#  before_filter :logged_in?

  def logged_in?(redirect = false)
    if cookies[:rh_user]
      username = cookies[:rh_user].split("|").first
      user = User.where(:username => username)
      if not user.empty?
        return true, user.first
      else
        new_user = User.new(:username => username)
        if new_user.save!
          return true, new_user
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
    if current_user
      current_user.admin?
    else
      false
    end
  end

  def current_user(redirect = false)
    bool, user = logged_in?(redirect)
    if bool
      return user
    end
    return nil
  end

helper_method :logged_in?, :current_user, :admin?

end
