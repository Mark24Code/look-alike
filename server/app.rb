require 'sinatra'
require 'sinatra/activerecord'
require 'rack/cors'
require 'json'
require 'cgi'
require 'fileutils'

# Configuration
set :database, { adapter: 'sqlite3', database: 'db/look_alike.sqlite3' }
set :port, 4567
set :bind, '0.0.0.0'

# Configure SQLite for better concurrency
configure do
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
  ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL")
  puts "SQLite WAL mode enabled"
end

# CORS
use Rack::Cors do
  allow do
    origins '*'
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :delete, :options]
  end
end

# Autoload Models
Dir["./models/*.rb"].each { |file| require file }
# Autoload Libs
Dir["./lib/*.rb"].each { |file| require file }

# Basic Error Handling
error do
  content_type :json
  status 500
  { error: env['sinatra.error'].message }.to_json
end

# Routes
get '/' do
  content_type :json
  { status: 'ok', version: '0.1.0' }.to_json
end

# API Controllers
Dir["./controllers/*.rb"].each { |file| require file }
