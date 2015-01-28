require 'test_helper'

class UsersControllerTest < ActionController::TestCase
  test "should get make_admin" do
    get :make_admin
    assert_response :success
  end

  test "should get remove_admin" do
    get :remove_admin
    assert_response :success
  end

end
