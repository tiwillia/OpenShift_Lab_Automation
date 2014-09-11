// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.
// You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/

$(document).ready(function() {
  $('.reachable_button').click(function() {
    var inst_id = $(this).attr("instance_id");
    console.log("Found the instance id:" + inst_id);
    $.getJSON("/instances/" + inst_id + "/reachable", function(result){
      console.log("Reachable: " + result.reachable);
      if (result.reachable === "true") {
        $('.reachable_button[instance_id="' + inst_id + '"]').replaceWith('<span class="glyphicon glyphicon-ok"></span>')
      } else {
        $('.reachable_button[instance_id="' + inst_id + '"]').replaceWith('<span class="glyphicon glyphicon-remove" title="' + result.err + '"></span>')
      }
    }); 
  });
});
