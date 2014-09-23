class WelcomeController < ApplicationController

  def index
  end  

  def help
    @questions = {"What is the purpose of this application?" => "purpose",
                  "None of the existing configurations work for my reproducer. Can I create my own environment?" => "my_own",
                  "How long does a deployment take?" => "deployment_time",
                  "Where are the OpenShift instances hosted?" => "hosted",
                  "How do the automatic deployments work?" => "deployments",
                  "Why can I not see the root passwords of instances?" => "root_passwd",
                  "What does it mean to 'check out' a lab?" => "check_out",
                  "What are the environment templates and how do I use them?" => "templates",
                  "Can the application deploy blank RHEL hosts?" => "blank_hosts",
                  "Can the application deploy highly available OpenShift environments?" => "ha"
                 }
  end

end
