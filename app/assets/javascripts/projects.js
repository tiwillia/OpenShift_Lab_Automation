// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.
// You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/

$(document).ready(function() {

  function reachable_check(inst_id) {
    $('.reachable_button_content[instance_id="' + inst_id + '"]').replaceWith('<div class="reachable_button_content" instance_id="' + inst_id + '"><img src="/assets/ajax-loader.gif" title="Working..." /></div>')
    console.log("Checking reachability for instance id:" + inst_id);
    $.getJSON("/instances/" + inst_id + "/reachable", function(result){
      console.log("Got result for " + inst_id + ": " + result.reachable);
      if (result.reachable === "true") {
        $('.reachable_button_content[instance_id="' + inst_id + '"]').replaceWith('<div class="reachable_button_content" instance_id="' + inst_id + '"><span class="text-success glyphicon glyphicon-ok" title="Success!"></span></div>')
      } else {
        $('.reachable_button_content[instance_id="' + inst_id + '"]').replaceWith('<div class="reachable_button_content" instance_id="' + inst_id + '"><span class="text-danger glyphicon glyphicon-remove" title="' + result.error + '"></span></div>')
      }
    }); 
  }

  $('.reachable_button').click(function() {
    var inst_id = $(this).attr("instance_id");
    reachable_check(inst_id);
  });

  $('.reachable_button_all').click(function(){
    var inst_id_list = $(this).attr("instance_ids").split(",");
    for (i = 0; i < inst_id_list.length; i++) {
      reachable_check(inst_id_list[i]);
    }
  });

});
