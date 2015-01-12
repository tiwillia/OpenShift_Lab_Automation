// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.
// You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/

$(document).ready(function() {

  if ($('.instance_id_list').length) {
    // This will be run right after the page is loaded
    $('#instanceLogTextArea').toggle();
    deployed_check_all();
    // If a deployment is in progress, check every 30 seconds.
    if ($('#in_progress').length) {
      console.log("Deployment is in progress, checking deployed status every 30 seconds");
      setInterval(deployed_check_all, 30000);
    };
  };

  function deployed_check_all() {
    console.log("Checking all instance deployed statuses...");
    var inst_id_list = $('.instance_id_list').attr("instance_ids").split(",");
    var proj_id = $('#project_page_header').attr("project_id");
    for (i = 0; i < inst_id_list.length; i++) {
      inst_id = inst_id_list[i];
      $('#deployed_glyph_' + inst_id).replaceWith('<img src="/assets/ajax-loader.gif" title="Working..." id="deployed_glyph_' + inst_id + '" />');
    };
    $.getJSON("/projects/" + proj_id + "/check_deployed", function(result) {
      console.log("Got result for project deployment check.");
      for (i = 0; i < inst_id_list.length; i++) {
        inst_id = inst_id_list[i];
        if (result[inst_id] === "deployed") {
          $('#deployed_glyph_' + inst_id).replaceWith('<span class="glyphicon glyphicon-ok" id="deployed_glyph_' + inst_id + '"></span>');
          var row=$('.instance_row[instance_id="' + inst_id + '"]');
          row.css("color", "#000000");
          if (row.hasClass("bg-info") || row.hasClass("bg-danger")) {
            console.log("row is:" + row);
            row.removeClass("bg-info bg-danger");
            row.addClass("bg-success");
          } else {
            row.addClass("bg-success");
          }; 
        } else if (result[inst_id] === "undeployed") {
          $('#deployed_glyph_' + inst_id).replaceWith('<span class="glyphicon glyphicon-remove" id="deployed_glyph_' + inst_id + '"></span>');
          var row=$('.instance_row[instance_id="' + inst_id + '"]');
          row.css("color", "#000000");
          if (row.hasClass("bg-success") || row.hasClass("bg-info")) {
            row.removeClass("bg-success bg-info");
            row.addClass("bg-danger");
          } else {
            row.addClass("bg-danger");
          };
          $('.console_link').replaceWith('<span class="glyphicon glyphicon-remove" id="console_glyph_<%= inst.id %>"></span>');
        } else if (result[inst_id] === "in_progress") {
          $('#deployed_glyph_' + inst_id).replaceWith('<span id="deployed_glyph_' + inst_id + '">In Progress</span>');
          var row=$('.instance_row[instance_id="' + inst_id + '"]');
          row.css("color", "#000000");
          if (row.hasClass("bg-success") || row.hasClass("bg-danger")) {
            row.removeClass("bg-success bg-danger");
            row.addClass("bg-info");
          } else {
            row.addClass("bg-info");
          };
        };
      };
    });
  };

  // Check to see if an instance is reachable via ssh, replace 'Reachable' entry in instance table
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

  // Check one for reachability
  $('.reachable_button').click(function() {
    var inst_id = $(this).attr("instance_id");
    reachable_check(inst_id);
  });

  // Check all for reachability
  $('.reachable_button_all').click(function(){
    var inst_id_list = $('.instance_id_list').attr("instance_ids").split(",");
    for (i = 0; i < inst_id_list.length; i++) {
      reachable_check(inst_id_list[i]);
    }
  });

  // Handle saving current configuration to a template
  $('.new_template_form').submit(function(){
    console.log("Submiting new template!");
    $('#newTemplate').modal("toggle");
    $('#new_template_button_content').replaceWith('<div id="new_template_button_content"><img src="/assets/ajax-loader.gif" title="Working..." /></div>');
    var valuesToSubmit = $(this).serialize();
    $.post("/templates", valuesToSubmit, function(result) {
      if (result.created === "true") {
      $('#new_template_button').replaceWith('<a href="/templates" class="btn btn-default"><div id="new_template_button_content"><span class="text-success">Template saved!</span></div></a>');
      };
    });
    return false;
  });

  // Handle javascript for textboxes in the new instance form
  $('#new_instance_check_box_no_openshift').change(function(){
    if (this.checked) {
      $('.new_instance_check_boxes').prop('checked', false); 
      $('.new_instance_check_boxes').prop('disabled', true); 
      $('.new_instance_gear_size').prop('disabled', true); 
    } else if (this.checked === false) {
      $('.new_instance_check_boxes').prop('disabled', false); 
    };
  });

  // Same as above, just for the edit instance form
  $('.edit_instance_check_box_no_openshift').change(function(){
    var inst_id = $(this).attr("instance_id");
    console.log(inst_id);
    if (this.checked) {
      $('.edit_instance_check_boxes[instance_id=' + inst_id  + ']').prop('checked', false); 
      $('.edit_instance_check_boxes[instance_id=' + inst_id  + ']').prop('disabled', true); 
      $('.edit_instance_gear_size[instance_id=' + inst_id  + ']').prop('disabled', true); 
    } else if (this.checked === false) {
      $('.edit_instance_check_boxes[instance_id=' + inst_id  + ']').prop('disabled', false); 
    };
  });

  $('.edit_instance_check_box_node').change(function(){
    var inst_id = $(this).attr("instance_id");
    if (this.checked) {
      $('.edit_instance_gear_size[instance_id=' + inst_id  + ']').prop('disabled', false); 
    } else if (this.checked === false) {
      $('.edit_instance_gear_size[instance_id=' + inst_id  + ']').prop('disabled', true); 
    };
  });

  $('#new_instance_check_box_node').change(function(){
    if (this.checked) {
      $('.new_instance_gear_size').prop('disabled', false); 
    } else if (this.checked === false) {
      $('.new_instance_gear_size').prop('disabled', true); 
    };
  
  });

  // Generate log for a specific instance in the instance log modal
  $('.instanceLogButton').click(function(){
      $('#instanceLogTextArea').val("");
      $('#instanceLogTextArea').hide();
      $('#instanceLogLoading').show();
    var inst_id = $(this).attr("instance_id");
    console.log("Instance log button pressed for instance " + inst_id);
    $.getJSON("/instances/" + inst_id + "/install_log", function(result){
      var textarea = $('#instanceLogTextArea')
      if (result.result == "success") {
        textarea.val(result.log_text);
      } else {
        textarea.val(result.message);
      };
      $('#instanceLogLoading').hide();
      textarea.show();
      textarea.scrollTop(textarea[0].scrollHeight - textarea.height());
    });
  });

  $(".console_link").click(function(e){
    // prevent the default shit from occuring
    e.preventDefault();

    var inst_id = $(this).data("instance");

    // if the console is already expanded, hide it and clear the canvas.
    if ($('#console_row_' + inst_id).hasClass('in')) {
      $('#console_row_' + inst_id).collapse('hide');
      $('#console_glyph_' + inst_id).replaceWith('<span class="glyphicon glyphicon-search" id="console_glyph_' + inst_id + '" ></span>');
      // should clear the canvas out, once we figure out how we are doing that
      return;
    };

    // replace glyphicon with loading gif
    $('#console_glyph_' + inst_id).replaceWith('<img src="/assets/ajax-loader.gif" title="Working..." id="console_glyph_' + inst_id + '" />');

    $.ajax({
      type: "GET",
      url: "/instances/" + inst_id + "/console",
      async: false,
      //dataType: "json",
      success: function(response, textStatus, jqXHR) {
        console.log("Successfully received VNC console link from API for instance " + inst_id);
        if (response['result'] === "success") {
          // add function call to function that adds <canvas> tag to accordian and populates it
          console.log(response['result'] + " : " + response['message'])
          open_console(inst_id, response['message']);
        } else {
          console.log("Failed to retrieve VNC console link from API: " + response['message']);
        };
      },
      error: function(jqXHR, textStatus, errorThrown) {
        console.log("Failed to retrieve VNC console link from API: " + errorThrown);
      }
    }); // end ajax

    // replace loading gif
    $('#console_glyph_' + inst_id).replaceWith('<span class="glyphicon glyphicon-chevron-up" id="console_glyph_' + inst_id + '" ></span>');
  }); // end  console_link listener
  

  // take two parameters: instance_id and console_url
  function open_console(inst_id, console_url){
    var divID = "#console_row_" + inst_id;
    var theRow = $(divID);

    console.log("Opening iframe for console url " + console_url);
    $('#console_td_' + inst_id).html('<iframe class="col-md-12" id="console_iframe_' + inst_id +'" frameborder="0" height="450px" src="' + console_url + '"></iframe>');
    $('#console_iframe_' + inst_id).focus();
    $('#console_iframe_' + inst_id).mouseover(function(){ $('#console_iframe_' + inst_id).focus(); });
    console.log("Attempting to open the hidden row for a console to instance " + inst_id);
    theRow.collapse('show');
  };
});

