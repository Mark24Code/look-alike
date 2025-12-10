require 'thread'

class WorkerPool
  def initialize(size = 4)
    @size = size
    @queue = Queue.new
    @threads = []
    @mutex = Mutex.new
    @results = []
  end

  def start
    # Clear any existing threads first
    stop if @threads.any?

    @threads = []
    @size.times do
      @threads << Thread.new do
        loop do
          job = @queue.pop
          break if job == :stop

          begin
            result = job.call
            @mutex.synchronize { @results << result } if result
          rescue => e
            puts "Worker error: #{e.message}"
            puts e.backtrace
          end
        end
      end
    end
  end

  def add_job(&block)
    @queue.push(block)
  end

  def stop
    return if @threads.empty?

    @size.times { @queue.push(:stop) }
    @threads.each(&:join)
    @threads = []
  end

  def results
    @mutex.synchronize { @results.dup }
  end
end
