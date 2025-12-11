namespace :project do
  desc "Reset all projects and related data"
  task :reset => :environment do
    puts "🔄 Resetting all projects..."

    # Stop all background threads
    puts "Stopping all background threads..."
    Project.all.each do |project|
      ThreadManager.stop_project_threads(project.id)
    end

    # Delete all data in reverse order of dependencies
    puts "Clearing comparison candidates..."
    ComparisonCandidate.delete_all

    puts "Clearing target selections..."
    TargetSelection.delete_all

    puts "Clearing source confirmations..."
    SourceConfirmation.delete_all

    puts "Clearing source files..."
    SourceFile.delete_all

    puts "Clearing target files..."
    TargetFile.delete_all

    puts "Clearing project targets..."
    ProjectTarget.delete_all

    puts "Clearing projects..."
    Project.delete_all

    # Reset auto-increment counters
    ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence WHERE name IN ('projects', 'project_targets', 'source_files', 'target_files', 'comparison_candidates', 'target_selections', 'source_confirmations')")

    puts "✅ All projects have been reset!"
    puts ""
    puts "Statistics:"
    puts "  Projects: #{Project.count}"
    puts "  Source Files: #{SourceFile.count}"
    puts "  Target Files: #{TargetFile.count}"
    puts "  Comparison Candidates: #{ComparisonCandidate.count}"
  end

  desc "Initialize a new project (simplified version)"
  task :init => :environment do
    require 'io/console'

    puts "🚀 Project Initialization Wizard"
    puts "=" * 50
    puts ""

    # Get project name
    print "Project name: "
    name = STDIN.gets.chomp

    if name.empty?
      puts "❌ Project name cannot be empty"
      exit 1
    end

    # Get source path
    print "Source path: "
    source_path = STDIN.gets.chomp.strip

    unless Dir.exist?(source_path)
      puts "❌ Error: Source path does not exist: #{source_path}"
      exit 1
    end

    # Get targets
    targets = []
    target_index = 1

    loop do
      puts ""
      puts "Target ##{target_index}"
      print "  Name (or press Enter to finish): "
      target_name = STDIN.gets.chomp.strip

      break if target_name.empty?

      print "  Path: "
      target_path = STDIN.gets.chomp.strip

      unless Dir.exist?(target_path)
        puts "  ⚠️  Warning: Path does not exist: #{target_path}"
        print "  Continue anyway? (y/N): "
        continue = STDIN.gets.chomp.downcase
        next unless continue == 'y'
      end

      targets << { 'name' => target_name, 'path' => target_path }
      target_index += 1
    end

    if targets.empty?
      puts "❌ At least one target is required"
      exit 1
    end

    # Summary
    puts ""
    puts "=" * 50
    puts "Summary:"
    puts "  Project name: #{name}"
    puts "  Source path: #{source_path}"
    targets.each do |target|
      puts "  Target (#{target['name']}): #{target['path']}"
    end
    puts ""
    print "Create this project? (y/N): "
    confirm = STDIN.gets.chomp.downcase

    unless confirm == 'y'
      puts "Cancelled."
      exit 0
    end

    # Create project
    puts ""
    puts "Creating project..."

    project = Project.create!(
      name: name,
      source_path: source_path,
      status: 'pending'
    )

    # Create targets
    targets.each do |target|
      project.project_targets.create!(
        name: target['name'],
        path: target['path']
      )
    end

    puts "✅ Project created successfully (ID: #{project.id})"
    puts ""
    puts "🔄 Starting background processing..."

    # Start background processing
    require_relative '../thread_manager'
    require_relative '../comparison_service'

    ThreadManager.start_comparison(project.id) do
      ComparisonService.new(project).process
    end

    puts "✅ Background processing started!"
    puts ""
    puts "Check progress with:"
    puts "  bundle exec rake project:status[#{project.id}]"
    puts ""
    puts "Or via web UI:"
    puts "  http://localhost:5173/projects/#{project.id}/compare"
  end

  desc "Quick init with command line arguments"
  task :quick_init, [:name, :source, :target1_name, :target1_path, :target2_name, :target2_path] => :environment do |t, args|
    name = args[:name]
    source_path = args[:source]

    unless name && source_path
      puts "❌ Usage: rake project:quick_init[name,source_path,target1_name,target1_path,target2_name,target2_path]"
      puts ""
      puts "Example:"
      puts "  rake project:quick_init[test,/path/to/source,de,/path/to/de,ta,/path/to/ta]"
      exit 1
    end

    unless Dir.exist?(source_path)
      puts "❌ Error: Source path does not exist: #{source_path}"
      exit 1
    end

    # Collect targets
    targets = []
    if args[:target1_name] && args[:target1_path]
      targets << { 'name' => args[:target1_name], 'path' => args[:target1_path] }
    end
    if args[:target2_name] && args[:target2_path]
      targets << { 'name' => args[:target2_name], 'path' => args[:target2_path] }
    end

    if targets.empty?
      puts "❌ At least one target is required"
      exit 1
    end

    # Verify target paths
    targets.each do |target|
      unless Dir.exist?(target['path'])
        puts "❌ Error: Target path does not exist: #{target['path']}"
        exit 1
      end
    end

    puts "🚀 Creating project: #{name}"
    puts "  Source: #{source_path}"
    targets.each do |target|
      puts "  Target (#{target['name']}): #{target['path']}"
    end
    puts ""

    # Create project
    project = Project.create!(
      name: name,
      source_path: source_path,
      status: 'pending'
    )

    # Create targets
    targets.each do |target|
      project.project_targets.create!(
        name: target['name'],
        path: target['path']
      )
    end

    puts "✅ Project created successfully (ID: #{project.id})"
    puts ""
    puts "🔄 Starting background processing..."

    # Start background processing
    require_relative '../thread_manager'
    require_relative '../comparison_service'

    ThreadManager.start_comparison(project.id) do
      ComparisonService.new(project).process
    end

    puts "✅ Background processing started!"
    puts ""
    puts "Check progress:"
    puts "  bundle exec rake project:status[#{project.id}]"
  end

  desc "Show project status"
  task :status, [:id] => :environment do |t, args|
    project_id = args[:id]

    unless project_id
      puts "📊 All Projects:"
      puts ""

      if Project.count == 0
        puts "No projects found."
        puts ""
        puts "Create a project with:"
        puts "  bundle exec rake project:init"
        exit 0
      end

      Project.all.each do |project|
        show_project_status(project)
      end
    else
      project = Project.find_by(id: project_id)

      unless project
        puts "❌ Project not found: #{project_id}"
        exit 1
      end

      show_project_status(project)
    end
  end

  desc "List all projects"
  task :list => :environment do
    if Project.count == 0
      puts "No projects found."
      puts ""
      puts "Create a project with:"
      puts "  bundle exec rake project:init"
      exit 0
    end

    puts "📋 Projects:"
    puts ""
    puts sprintf("%-5s %-20s %-15s %-10s", "ID", "Name", "Status", "Progress")
    puts "-" * 55

    Project.all.each do |project|
      total = project.source_files.count
      processed = project.source_files.where(status: 'analyzed').count
      progress = total > 0 ? "#{processed}/#{total}" : "0/0"

      puts sprintf("%-5d %-20s %-15s %-10s",
        project.id,
        project.name.length > 20 ? project.name[0..16] + "..." : project.name,
        project.status,
        progress
      )
    end

    puts ""
    puts "Run 'bundle exec rake project:status[ID]' for detailed information"
  end

  desc "Delete a project"
  task :delete, [:id] => :environment do |t, args|
    project_id = args[:id]

    unless project_id
      puts "❌ Usage: rake project:delete[id]"
      exit 1
    end

    project = Project.find_by(id: project_id)

    unless project
      puts "❌ Project not found: #{project_id}"
      exit 1
    end

    puts "🗑️  Deleting project: #{project.name} (ID: #{project.id})"

    # Stop background threads
    ThreadManager.stop_project_threads(project.id)

    # Delete project (cascades to all related records)
    project.destroy

    puts "✅ Project deleted successfully!"
  end

  def show_project_status(project)
    total_files = project.source_files.count
    processed_files = project.source_files.where(status: 'analyzed').count
    progress = total_files > 0 ? (processed_files.to_f / total_files * 100).round(2) : 0

    puts "Project: #{project.name} (ID: #{project.id})"
    puts "  Status: #{project.status}"
    puts "  Source: #{project.source_path}"

    project.project_targets.each do |target|
      target_file_count = target.target_files.count
      puts "  Target (#{target.name}): #{target.path} (#{target_file_count} files)"
    end

    puts "  Progress: #{processed_files}/#{total_files} files (#{progress}%)"

    if project.started_at
      puts "  Started: #{project.started_at.strftime('%Y-%m-%d %H:%M:%S')}"
    end

    if project.ended_at
      duration = (project.ended_at - project.started_at).round(2)
      puts "  Completed: #{project.ended_at.strftime('%Y-%m-%d %H:%M:%S')} (took #{duration}s)"
    end

    if project.error_message
      puts "  Error: #{project.error_message}"
    end

    # Show statistics
    candidate_count = ComparisonCandidate.joins(:source_file)
      .where(source_files: { project_id: project.id })
      .count

    confirmed_count = SourceConfirmation.joins(:source_file)
      .where(source_files: { project_id: project.id }, confirmed: true)
      .count

    puts ""
    puts "  Statistics:"
    puts "    - Source files: #{total_files}"
    puts "    - Target files: #{project.project_targets.sum { |t| t.target_files.count }}"
    puts "    - Comparison candidates: #{candidate_count}"
    puts "    - Confirmed selections: #{confirmed_count}"
    puts ""
  end
end

# Add environment task
task :environment do
  require './app'
end
