//Place all the behaviors and hooks related to the matching controller here.
//All this logic will automatically be available in application.js.
// You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/

$(document).ready(function() {

  $('.apply_template_form').submit(function(){
    var template_id = $(this)[0].id.split("_")[2];
    $('#apply_template_button_' + template_id).replaceWith("<a class=\"btn btn-sm btn-warning\" id=\"apply_template_button_" + template_id  + "\"><img src=\"/assets/ajax-loader.gif\" title=\"Working...\"></a>");
    var valuesToSubmit = $(this).serialize();
    $.post("/templates/" + template_id + "/apply", valuesToSubmit, function(result) {
      if (result.applied === "true") {
        $('#apply_template_button_' + template_id).replaceWith('<a href="/projects/' + result.project_id  + '" class="btn btn-sm btn-success">Template applied!</a>');
      } else {
        $('#apply_template_button_' + template_id).replaceWith('<a href="/projects/' + result.project_id + '" class="btn btn-sm btn-danger">Failure - Contact admin</a>');
      };
    });
    return false;
  });

});
