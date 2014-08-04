#! /usr/bin/env oo-ruby

# This script will stress test an environment by creating and deleting applications concurrently.
# The number of concurrent threads and the number of create/deletes per thread can be configured.
# The cartridge(s) used can also be configured

# This script MUST be run with the ruby193-SCL version of ruby:
#    $ oo-ruby stress_test.rb

# CONFIGURE THESE #
num_threads = 10
apps_per_thread = 5
app_carts = "jbossews-1.0"
# --------------- #

threads = []

num_threads.times do |thread_index|
  threads << Thread.new do
    begin
      File.open("thread#{thread_index}.log", 'w') do |f|
        apps_per_thread.times do |app_index|
          app_name = "test#{thread_index}x#{app_index}"
          puts app_name

          f.sync = true
          t = rand(1.0..4.0)
          f.puts "Sleeping #{t}"
          sleep t

          cmd = "rhc app-create #{app_name} #{app_carts} --no-keys --no-git --no-dns"
          f.puts "Running '#{cmd}'"
          f.puts `#{cmd}`

          t = rand(3.0..6.0)
          f.puts "Sleeping #{t}"
          sleep t

          cmd = "rhc app-delete #{app_name} --confirm"
          f.puts "Running '#{cmd}'"
          f.puts `#{cmd}`

          t = rand(1.0..6.0)
          f.puts "Sleeping #{t}"
          sleep t
        end
      end
    rescue => e
      puts "Failed " + e.inspect
    end
  end
end
threads.each { |t| t.join }
puts "Stess test completed."
