# Set up the global variable $redis with a connection to the redis store
host = ENV['OPENSHIFT_REDIS_HOST'] || CONFIG[:redis_host] || "localhost"
port = ENV['OPENSHIFT_REDIS_PORT'] || CONFIG[:redis_port] || 6379
password = ENV['REDIS_PASSWORD'] || CONFIG[:redis_password] || nil
if password
  $redis = Redis.new(:host => host, :port => port, :password => password)
else
  $redis = Redis.new(:host => host, :port => port)
end
