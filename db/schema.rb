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

ActiveRecord::Schema.define(:version => 20140730150736) do

  create_table "instances", :force => true do |t|
    t.text     "name"
    t.text     "types"
    t.text     "floating_ip"
    t.text     "internal_ip"
    t.text     "fqdn"
    t.integer  "project_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.text     "root_password"
  end

  create_table "labs", :force => true do |t|
    t.text     "name"
    t.text     "controller"
    t.text     "geo"
    t.text     "username"
    t.text     "password"
    t.text     "api_url"
    t.text     "auth_tenant"
    t.datetime "created_at",  :null => false
    t.datetime "updated_at",  :null => false
  end

  create_table "projects", :force => true do |t|
    t.text     "name"
    t.text     "network"
    t.text     "image"
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
    t.datetime "created_at",              :null => false
    t.datetime "updated_at",              :null => false
  end

end
