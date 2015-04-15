#OpenShift Labs
 
This application was designed to manage and deploy OpenShift instances for testing purposes. The OpenShift deployments are not designed to be permanent, but instead to be re-deployed repeatedly. 

The application supports automatic deployment of small and extremely large OpenShift deployments. Deploying HA datastores and activemq servers is also supported. Deploying fully HA environments with HA brokers and an external load balancer is not yet supported.

##How can I contribute?

Fork this repository into your own, create a new branch (optional), edit the code, and push to your repository. You can then make a pull request to this repository.

Any contributions are welcome!

##How can I deploy my own?
 
This application runs on OpenShift primarily, but can be run on passenger hosts. To deploy to OpenShift, first create a Ruby 1.9 application with a Mysql-5 cartridge:
```
rhc app create APP_NAME ruby-1.9 mysql-5.5
```
  
After you have a rails application, git clone the application locally (done automatically with the above command), change into the cloned application directory, and run the below to merge the OpenShift lab Automation code into your application:
```
git remote add upstream -m master https://github.com/tiwillia/OpenShift_Lab_Automation.git
git pull -s recursive -X theirs upstream master
```

Modify the configuration file for the application. The configuration file is located at *./config/application.yml.example* and should be changed to *./config/application.yml*. Modify the configuration file as appropriate, then scp it your application's data directory:
```
rhc app-show APP_NAME   # This will give you the ssh url used in the next command
scp ./config/application.yml UUID@APP_URL:~/app-root/data
```

Finally, push your code to the application!
```
git push
```
