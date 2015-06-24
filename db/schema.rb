# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20150624152734) do

  create_table "delayed_jobs", :force => true do |t|
    t.integer  "priority",   :default => 0, :null => false
    t.integer  "attempts",   :default => 0, :null => false
    t.text     "handler",                   :null => false
    t.text     "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at",                :null => false
    t.datetime "updated_at",                :null => false
  end

  add_index "delayed_jobs", ["priority", "run_at"], :name => "delayed_jobs_priority"

  create_table "deployments", :force => true do |t|
    t.integer  "v2_project_id"
    t.integer  "started_by"
    t.text     "action"
    t.boolean  "complete",       :default => false
    t.boolean  "started",        :default => false
    t.datetime "started_time"
    t.datetime "completed_time"
    t.datetime "created_at",                        :null => false
    t.datetime "updated_at",                        :null => false
    t.integer  "v2_instance_id"
    t.text     "status"
    t.integer  "job_id"
  end

  create_table "labs", :force => true do |t|
    t.text     "name"
    t.text     "controller"
    t.text     "geo"
    t.text     "username"
    t.text     "password"
    t.text     "api_url"
    t.text     "auth_tenant"
    t.datetime "created_at",                                 :null => false
    t.datetime "updated_at",                                 :null => false
    t.integer  "default_quota_instances", :default => 15
    t.integer  "default_quota_cores",     :default => 45
    t.integer  "default_quota_ram",       :default => 30720
    t.text     "nameservers"
  end

  create_table "templates", :force => true do |t|
    t.integer  "v2_project_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.string   "name"
    t.text     "description"
    t.string   "file_location"
    t.text     "content"
    t.integer  "created_by"
  end

  create_table "users", :force => true do |t|
    t.string   "first_name"
    t.string   "last_name"
    t.string   "username"
    t.string   "email"
    t.boolean  "admin",      :default => false
    t.datetime "created_at",                    :null => false
    t.datetime "updated_at",                    :null => false
  end

  create_table "v2_instances", :force => true do |t|
    t.text     "name"
    t.text     "types"
    t.text     "floating_ip"
    t.text     "internal_ip"
    t.text     "fqdn"
    t.integer  "v2_project_id"
    t.datetime "created_at",                                :null => false
    t.datetime "updated_at",                                :null => false
    t.text     "root_password"
    t.text     "install_variables"
    t.string   "gear_size"
    t.string   "flavor"
    t.string   "image"
    t.boolean  "deployment_started",     :default => false
    t.boolean  "deployment_completed",   :default => false
    t.boolean  "reachable",              :default => false
    t.datetime "last_checked_reachable"
    t.boolean  "no_openshift",           :default => false
    t.string   "uuid"
  end

  create_table "v2_projects", :force => true do |t|
    t.text     "name"
    t.text     "network"
    t.text     "security_group"
    t.text     "domain"
    t.text     "floating_ips"
    t.text     "availability_zone"
    t.text     "mcollective_username"
    t.text     "mcollective_password"
    t.text     "activemq_admin_password"
    t.text     "activemq_user_password"
    t.text     "mongodb_username"
    t.text     "mongodb_password"
    t.text     "mongodb_admin_username"
    t.text     "mongodb_admin_password"
    t.text     "openshift_username"
    t.text     "openshift_password"
    t.text     "bind_key"
    t.text     "valid_gear_sizes"
    t.integer  "lab_id"
    t.datetime "created_at",                                   :null => false
    t.datetime "updated_at",                                   :null => false
    t.string   "ose_version"
    t.integer  "checked_out_by"
    t.datetime "checked_out_at"
    t.boolean  "deployed",                  :default => false
    t.string   "uuid"
    t.boolean  "hidden",                    :default => false
    t.date     "inactive_reminder_sent_at"
  end

end
