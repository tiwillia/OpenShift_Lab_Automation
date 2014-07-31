source 'https://rubygems.org'

gem 'rails', '~> 3.2.16'
gem 'rack', '~> 1.4.5'

# Bundle edge Rails instead:
# gem 'rails', :git => 'git://github.com/rails/rails.git'

group :production, :mysql do
  gem 'mysql2'
end

group :production, :postgresql do
  gem 'pg'
end

group :development, :test do
  gem 'sqlite3'
  gem 'minitest' # Necessary to bring up the rails console from inside a gear
  gem 'pry'      # Way helpful in development
  gem 'thor', '= 0.14.6'
end

# Gems used only for assets and not required
# in production environments by default.
group :assets do
  gem 'sass-rails'
  gem 'coffee-rails'

  # See https://github.com/sstephenson/execjs#readme for more supported runtimes
  # gem 'therubyracer', :platforms => :ruby

  gem 'uglifier', '>= 1.0.3'
end

# Beautify that app
gem 'jquery-rails'

# To use ActiveModel has_secure_password
# gem 'bcrypt-ruby', '~> 3.0.0'

# To use Jbuilder templates for JSON
# gem 'jbuilder'

# Use unicorn as the app server
# gem 'unicorn'

# Deploy with Capistrano
# gem 'capistrano'

# To use debugger
# gem 'debugger'

# Strong parameters is built into rails 4, so lets use it
gem 'strong_parameters'

# Gotta talk to openstack somehow
gem 'openstack'

# This integrates twitter's bootstrap
gem "therubyracer"
gem "less-rails" #Sprockets (what Rails 3.1 uses for its asset pipeline) supports LESS
gem "twitter-bootstrap-rails",
  :git => 'git://github.com/seyhunak/twitter-bootstrap-rails.git',
  :branch => 'bootstrap3'
gem 'jquery-ui-rails'

# We need to be able to run commands on instances
gem 'net-ssh'
