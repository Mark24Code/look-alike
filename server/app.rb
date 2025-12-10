require 'sinatra'
require 'sinatra/activerecord'
require 'rack/cors'
require 'json'
require 'cgi'
require 'fileutils'

# Configuration
set :database, { adapter: 'sqlite3', database: 'db/look_alike.sqlite3' }
set :port, 4568
set :bind, '0.0.0.0'
set :public_folder, '../client/dist'

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
# Health check endpoint
get '/api/health' do
  content_type :json
  { status: 'ok', version: '0.1.0' }.to_json
end

# API Controllers
Dir["./controllers/*.rb"].each { |file| require file }

# Serve frontend static files in production mode
# This should be at the end to act as a fallback for all non-API routes
get '*' do
  if File.exist?(File.join(settings.public_folder, 'index.html'))
    send_file File.join(settings.public_folder, 'index.html')
  else
    content_type :json
    { error: 'Frontend assets not found. Please run "cd client && npm run build" first.' }.to_json
  end
end
