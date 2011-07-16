#!/usr/bin/env ruby
require 'logger'
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../../lib'
require 'app'
require 'doozque/server'

use Rack::ShowExceptions

# Set the AUTH env variable to your basic auth password to protect Doozque.
AUTH_PASSWORD = ENV['AUTH']
if AUTH_PASSWORD
  Doozque::Server.use Rack::Auth::Basic do |username, password|
    password == AUTH_PASSWORD
  end
end

run Rack::URLMap.new \
  "/"       => Demo::App.new,
  "/doozque" => Doozque::Server.new
