class SessionsController < ApplicationController

  def new
  end

  # Start a new user session
  def create
  end

  # End user session
  def destroy
  end

private

  def create_params
    params.permit!
  end

end

