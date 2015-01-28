// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

$(document).ready(function() {

  $('.check_out_button').click(function() {
    var element = $(this)
    var project_id = element.attr("project_id");
    console.log("checking out project " + project_id);
    $.getJSON("/projects/" + project_id + "/check_out", function(result) {
      if (result["success"] === true) {
        console.log("Successfully checked out project");
        element.hide();
        $(".uncheck_out_button[project_id=" + project_id + "]").show();
        $("#checked_out_by_" + project_id).html(result["user"]);
        $("#checked_out_since_" + project_id).html(result["time"]);
      } else {
        console.log("Couldn't check out project: " + result["message"] + result["success"]);
      };
    });
  });

  $('.uncheck_out_button').click(function() {
    var element = $(this)
    var project_id = element.attr("project_id");
    console.log("unchecking out project " + project_id);
    $.getJSON("/projects/" + project_id + "/uncheck_out", function(result) {
      if (result["success"] === true) {
        console.log("Successfully unchecked out project");
        element.hide();
        $(".check_out_button[project_id=" + project_id + "]").show();
        $("#checked_out_by_" + project_id).html("Nobody");
        $("#checked_out_since_" + project_id).html("");
      } else {
        console.log("Couldn't uncheck out project: " + result["message"] + result["success"]);
      };
    });
  });


  $('.make_admin_button').click(function() {
    var element = $(this)
    var user_id = element.attr("user_id");
    console.log("Making user " + user_id + " an admin.");
    $.getJSON("/users/" + user_id + "/make_admin", function(result) {
      if (result["success"] === true) {
        console.log("Successfully made user an admin");
        element.hide();
        $(".remove_admin_button[user_id=" + user_id + "]").show();
        $("#admin_bool_" + user_id).html('<span class="glyphicon glyphicon-ok"></span>');
      } else {
        console.log("Could not make user an admin: " + result["message"]);
      };
    });
  });


  $('.remove_admin_button').click(function() {
    var element = $(this)
    var user_id = element.attr("user_id");
    console.log("Removing user " + user_id + " as an admin.");
    $.getJSON("/users/" + user_id + "/remove_admin", function(result) {
      if (result["success"] === true) {
        console.log("Successfully removed user as an admin");
        element.hide();
        $(".make_admin_button[user_id=" + user_id + "]").show();
        $("#admin_bool_" + user_id).html('<span class="glyphicon glyphicon-remove"></span>');
      } else {
        console.log("Could not make user an admin: " + result["message"]);
      };
    });
  });

});
