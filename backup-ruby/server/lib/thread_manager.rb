# Thread Manager for Background Jobs
# Tracks and manages background threads for projects

class ThreadManager
  @threads = {}
  @mutex = Mutex.new

  class << self
    def start_comparison(project_id, &block)
      stop_project_threads(project_id) # Stop any existing threads

      thread = Thread.new do
        begin
          block.call
        rescue => e
          puts "Comparison thread error for project #{project_id}: #{e.message}"
          puts e.backtrace
        ensure
          remove_thread(project_id, :comparison)
        end
      end

      add_thread(project_id, :comparison, thread)
      thread
    end

    def start_export(project_id, &block)
      # Don't stop comparison thread when exporting
      stop_thread(project_id, :export) # Stop any existing export thread

      thread = Thread.new do
        begin
          block.call
        rescue => e
          puts "Export thread error for project #{project_id}: #{e.message}"
          puts e.backtrace
        ensure
          remove_thread(project_id, :export)
        end
      end

      add_thread(project_id, :export, thread)
      thread
    end

    def stop_project_threads(project_id)
      @mutex.synchronize do
        if @threads[project_id]
          @threads[project_id].each do |type, thread|
            stop_thread_instance(thread, "project #{project_id} #{type}")
          end
          @threads.delete(project_id)
        end
      end
    end

    def stop_thread(project_id, type)
      @mutex.synchronize do
        if @threads[project_id] && @threads[project_id][type]
          thread = @threads[project_id][type]
          stop_thread_instance(thread, "project #{project_id} #{type}")
          @threads[project_id].delete(type)
          @threads.delete(project_id) if @threads[project_id].empty?
        end
      end
    end

    def active_threads(project_id = nil)
      @mutex.synchronize do
        if project_id
          @threads[project_id]&.keys || []
        else
          @threads.keys
        end
      end
    end

    def has_active_threads?(project_id)
      @mutex.synchronize do
        @threads[project_id]&.any? { |_, thread| thread.alive? } || false
      end
    end

    private

    def add_thread(project_id, type, thread)
      @mutex.synchronize do
        @threads[project_id] ||= {}
        @threads[project_id][type] = thread
      end
    end

    def remove_thread(project_id, type)
      @mutex.synchronize do
        if @threads[project_id]
          @threads[project_id].delete(type)
          @threads.delete(project_id) if @threads[project_id].empty?
        end
      end
    end

    def stop_thread_instance(thread, description)
      if thread&.alive?
        puts "Stopping thread for #{description}..."
        thread.kill
        thread.join(2) # Wait up to 2 seconds for thread to finish
        puts "Thread for #{description} stopped"
      end
    end
  end
end
