source 'https://rubygems.org'


# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '4.2.3'
# Use sqlite3 as the database for Active Record
#gem 'sqlite3'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 4.0.3'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# Use CoffeeScript for .js.coffee assets and views
gem 'coffee-rails', '~> 4.0.0'
# See https://github.com/sstephenson/execjs#readme for more supported runtimes
# gem 'therubyracer',  platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'
gem "jquery-ui-rails", '3.0.1'  #loads jquery ui v 1.9.2
# Turbolinks makes following links in your web application faster. Read more: https://github.com/rails/turbolinks
# gem 'turbolinks'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.0'
# bundle exec rake doc:rails generates the API under doc/api.
gem 'sdoc', '~> 0.4.0',          group: :doc

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use unicorn as the app server
# gem 'unicorn'

# Use debugger
# gem 'debugger', group: [:development, :test]

# Leverage action caching for WMS server
gem 'actionpack-action_caching'

# Locked to .20 to prevent deprecation warnings
# This is fixed in rails 5.0
gem 'pg', '0.20.0'

#gem 'activerecord-postgis-adapter'
gem 'activerecord-postgis-adapter', '~>3.0'

gem 'paperclip', '~> 4.2.0'

gem 'will_paginate', '~> 3.0'
gem 'spawnling', '~>2.1'


gem 'paper_trail', '~>4.0.0.rc1'

gem 'gdal'
gem 'georuby'
gem 'geoplanet'
gem 'yql', '0.0.2'

gem "rmagick"


# Used for caching files to S3
gem "s3"

# Why is this here?
gem 'redis-activesupport'

group :development do
   gem 'web-console', '~> 2.0'
   gem 'spring'
   gem 'thin'
   gem 'capistrano', '~> 3.2.1'
   gem 'capistrano-rails',    :require => false
   gem 'capistrano-bundler',  :require => false
   gem 'rvm1-capistrano3',    :require => false
end

group :test do
  gem 'vcr'
  gem 'webmock'
end
