class UsersController < ApplicationController

  before_filter :is_admin?

  def make_admin
    @user = User.find(params[:id])
    if @user.update_attributes(:admin => true)
      respond_to do |format|
        format.json {
          render :json => {:success => true}
        }
      end
    else
      respond_to do |format|
        format.json {
          render :json => {:success => false, :message => "Could not update user to an admin."}
        }
      end
    end
  end

  def remove_admin
    @user = User.find(params[:id])
    if @user.update_attributes(:admin => false)
      respond_to do |format|
        format.json {
          render :json => {:success => true}
        }
      end
    else
      respond_to do |format|
        format.json {
          render :json => {:success => false, :message => "Could not update user to no longer be an admin."}
        }
      end
    end
  end

  private

  def is_admin?
    if current_user.nil? || !current_user.admin?
      flash[:error] = "You must be an administrator to perform this action."
      redirect_to :back
    end
  end

end
