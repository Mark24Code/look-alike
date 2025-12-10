class ProjectsController < Sinatra::Base
  # Inherit/Mixin generic config if needed, but Sinatra::Base is fine.
  # We might need to duplicate the CORS/DB setup if not inheriting from App, 
  # but usually we just register 'controllers' in the main App or use `class App < Sinatra::Base`.
  # For this simple app, let's just make it a part of the main application namespace or register routes.
  
  # Simplest way in modular Sinatra app structure:
  # Just open the main class or define routes.
end

# Let's use the main App class directly or a clean routing file.
# Since app.rb requires everything, let's just write top-level routes 
# or use a class that maps to a namespace.

# Let's go with top-level routes style for simplicity in this file,
# which `app.rb` requires.
# BUT `app.rb` requires `controllers/*.rb`.

# /controllers/projects_controller.rb
get '/api/projects' do
  content_type :json
  page = params[:page].to_i
  page = 1 if page < 1
  per_page = 20

  projects = Project.order(created_at: :desc).limit(per_page).offset((page - 1) * per_page)
  total = Project.count

  # Add statistics for each project
  projects_with_stats = projects.map do |project|
    total_files = project.source_files.count
    confirmed_files = project.source_files.joins(:source_confirmation).where(source_confirmations: { confirmed: true }).count

    project.as_json(methods: [:output_path]).merge(
      confirmation_stats: {
        confirmed: confirmed_files,
        total: total_files
      }
    )
  end

  {
    projects: projects_with_stats,
    total: total,
    page: page,
    per_page: per_page
  }.to_json
end

post '/api/projects' do
  content_type :json
  data = JSON.parse(request.body.read)
  
  project = Project.new(
    name: data['name'],
    source_path: data['source_path']
  )
  
  if project.save
    # Create Targets
    (data['targets'] || []).each do |t|
      project.project_targets.create(name: t['name'], path: t['path'])
    end

    # Start Background Job with Thread Manager
    ThreadManager.start_comparison(project.id) do
      ComparisonService.new(project).process
    end

    project.to_json
  else
    status 422
    { error: project.errors.full_messages }.to_json
  end
end

get '/api/projects/:id' do
  content_type :json
  project = Project.find(params[:id])

  # Progress stats
  total_files = project.source_files.count
  processed = project.source_files.where(status: 'analyzed').count

  # Check for duplicate file names
  duplicates = project.source_files
    .select('relative_path')
    .group('relative_path')
    .having('COUNT(*) > 1')
    .pluck('relative_path')

  # Get all files with duplicate names
  duplicate_files = []
  if duplicates.any?
    duplicates.each do |rel_path|
      files = project.source_files.where(relative_path: rel_path).pluck(:full_path)
      duplicate_files << {
        relative_path: rel_path,
        count: files.count,
        files: files
      }
    end
  end

  project.as_json.merge(
    stats: {
      total_files: total_files,
      processed: processed,
      progress: total_files > 0 ? (processed.to_f / total_files * 100).round(2) : 0
    },
    targets: project.project_targets.map { |t| { id: t.id, name: t.name, path: t.path } },
    duplicate_warnings: duplicate_files
  ).to_json
end

delete '/api/projects/:id' do
  content_type :json
  project = Project.find(params[:id])
  project_id = project.id

  # Stop all background threads for this project
  ThreadManager.stop_project_threads(project_id)

  # Delete project and all related records (via dependent: :destroy)
  project.destroy

  { status: 'deleted', message: 'Project and all related data deleted, background tasks stopped' }.to_json
end

# Files Tree Structure
get '/api/projects/:id/files' do
  content_type :json
  project = Project.find(params[:id])
  
  # Return recursive tree or flat list?
  # Tree is better for UI.
  # We can construct tree from relative_paths.
  
  files = project.source_files.select(:id, :relative_path, :status, :width, :height).all
  
  # Simple directory tree construction
  tree = { name: "root", key: "root", children: [] }
  
  files.each do |f|
    parts = f.relative_path.split('/')
    current = tree
    
    parts.each_with_index do |part, idx|
      is_file = (idx == parts.size - 1)
      
      existing = current[:children].find { |c| c[:name] == part }
      
      if existing
        current = existing
      else
        new_node = {
          name: part,
          key: is_file ? "file-#{f.id}" : "dir-#{current[:key]}-#{part}",
          children: [],
          isLeaf: is_file
        }
        if is_file
          new_node.merge!(
            file_id: f.id,
            status: f.status,
            dimensions: "#{f.width}x#{f.height}"
          )
        end
        current[:children] << new_node
        current = new_node
      end
    end
  end
  
  tree.to_json
end

# Get candidates for a specific file (or batch)
# Now returns arrays of candidates for each target with target_selections and confirmation status
post '/api/projects/:id/candidates' do
  content_type :json
  data = JSON.parse(request.body.read)
  file_ids = data['file_ids']

  results = {}

  source_files = SourceFile
    .includes(:comparison_candidates, :target_selections, :source_confirmation)
    .where(id: file_ids)

  project = Project.find(params[:id])

  source_files.each do |sf|
    candidates = {}
    target_selections_hash = {}

    # Group candidates by target
    sf.comparison_candidates.group_by(&:project_target_id).each do |tid, cands|
      target = ProjectTarget.find(tid)
      t_name = target.name

      # Sort by rank or score
      sorted = cands.sort_by { |c| c.rank || 999 }

      candidates[t_name] = sorted.map do |c|
        {
          id: c.id,
          path: c.file_path,
          similarity: c.similarity_score,
          width: c.width,
          height: c.height
        }
      end
    end

    # Get target selections for each target
    project.project_targets.each do |target|
      selection = sf.target_selections.find { |ts| ts.project_target_id == target.id }

      target_selections_hash[target.name] = if selection
        {
          selected_candidate_id: selection.selected_candidate_id,
          no_match: selection.no_match || false
        }
      else
        {
          selected_candidate_id: nil,
          no_match: false
        }
      end
    end

    # Get confirmation status
    confirmation = sf.source_confirmation
    confirmed = confirmation ? confirmation.confirmed : false

    results[sf.id] = {
      source: {
        path: sf.full_path,
        relative: sf.relative_path,
        thumb_url: "/api/image?path=#{CGI.escape(sf.full_path)}",
        width: sf.width,
        height: sf.height,
        size_bytes: sf.size_bytes
      },
      candidates: candidates,
      target_selections: target_selections_hash,
      confirmed: confirmed
    }
  end

  results.to_json
end

# Route to serve local images (quick and dirty for local tool)
get '/api/image' do
  path = params[:path]
  if File.exist?(path)
    send_file path
  else
    status 404
  end
end

# Select a candidate for a specific target
post '/api/projects/:id/select_candidate' do
  content_type :json
  data = JSON.parse(request.body.read)
  source_file_id = data['source_file_id']
  project_target_id = data['project_target_id']
  selected_candidate_id = data['selected_candidate_id']

  target_selection = TargetSelection.find_or_initialize_by(
    source_file_id: source_file_id,
    project_target_id: project_target_id
  )

  target_selection.selected_candidate_id = selected_candidate_id
  target_selection.no_match = false
  target_selection.save!

  { status: 'ok' }.to_json
end

# Mark a target as having no match
post '/api/projects/:id/mark_no_match' do
  content_type :json
  data = JSON.parse(request.body.read)
  source_file_id = data['source_file_id']
  project_target_id = data['project_target_id']

  target_selection = TargetSelection.find_or_initialize_by(
    source_file_id: source_file_id,
    project_target_id: project_target_id
  )

  target_selection.selected_candidate_id = nil
  target_selection.no_match = true
  target_selection.save!

  { status: 'ok' }.to_json
end

# Confirm/unconfirm entire row (all targets for a source file)
post '/api/projects/:id/confirm_row' do
  content_type :json
  data = JSON.parse(request.body.read)
  source_file_id = data['source_file_id']
  confirmed = data['confirmed']

  confirmation = SourceConfirmation.find_or_initialize_by(source_file_id: source_file_id)
  confirmation.confirmed = confirmed
  confirmation.confirmed_at = confirmed ? Time.now : nil
  confirmation.save!

  { status: 'ok' }.to_json
end

post '/api/projects/:id/export' do
  content_type :json
  data = JSON.parse(request.body.read) rescue {}
  project = Project.find(params[:id])

  use_placeholder = data['use_placeholder'].nil? ? true : data['use_placeholder']
  only_confirmed = data['only_confirmed'] || false

  ThreadManager.start_export(project.id) do
    ExportService.new(project, use_placeholder: use_placeholder, only_confirmed: only_confirmed).process
  end

  { status: 'exporting' }.to_json
end

get '/api/projects/:id/export_progress' do
  content_type :json
  project = Project.find(params[:id])

  progress_file = File.join(project.output_path, '.export_progress.json')
  if File.exist?(progress_file)
    progress_data = JSON.parse(File.read(progress_file))
    progress_data.to_json
  else
    { total: 0, processed: 0, current: "" }.to_json
  end
rescue => e
  status 500
  { error: e.message }.to_json
end
