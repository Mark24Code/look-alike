require_relative 'worker_pool'
require_relative 'image_comparator'

class IndexingService
  BATCH_SIZE = 100  # 每批次插入100条记录

  def initialize(project)
    @project = project
    @worker_pool = WorkerPool.new(4)  # 4个工作线程
    @source_batch = []
    @target_batches = {}  # target_id => batch array
    @mutex = Mutex.new
  end

  def process
    puts "\n========================================="
    puts "IndexingService.process started"
    puts "Project: #{@project.name} (ID: #{@project.id})"
    puts "Source path: #{@project.source_path}"
    puts "========================================="

    @project.update(status: 'indexing')

    begin
      # 索引source文件（并行处理 + 批量插入）
      index_source_files

      # 索引target文件（并行处理 + 批量插入）
      index_target_files

      @project.update(status: 'indexed')
      puts "\n[SUCCESS] IndexingService completed"
      puts "========================================="
    rescue => e
      @project.update(status: 'error', error_message: e.message)
      puts "\n[ERROR] IndexingService error: #{e.message}"
      puts "[ERROR] Backtrace:"
      puts e.backtrace.join("\n")
      puts "========================================="
    end
  end

  private

  def index_source_files
    puts "\n[SOURCE] Scanning source directory: #{@project.source_path}"

    # 检查路径是否存在（去除空格）
    source_path = @project.source_path.strip
    unless Dir.exist?(source_path)
      puts "[ERROR] Source path does not exist: '#{@project.source_path}'"
      puts "[ERROR] Path after strip: '#{source_path}'"
      return
    end

    images = Dir.glob(File.join(source_path, "**", "*.{jpg,jpeg,png,webp,bmp}"), File::FNM_CASEFOLD)

    puts "[SOURCE] Found #{images.size} source images to index"

    if images.empty?
      puts "[WARNING] No source images found! Check:"
      puts "  - Path exists: #{Dir.exist?(source_path)}"
      puts "  - Path readable: #{File.readable?(source_path)}"
      puts "  - Sample files: #{Dir.glob(File.join(source_path, '*')).first(5).join(', ')}"
    end

    # 批量检查已存在的文件（避免 N+1 查询）
    existing_paths = SourceFile.where(project: @project)
                               .pluck(:relative_path)
                               .to_set

    # 过滤掉已存在的文件
    new_images = images.reject do |full_path|
      relative_path = Pathname.new(full_path).relative_path_from(Pathname.new(source_path)).to_s
      existing_paths.include?(relative_path)
    end

    puts "[SOURCE] #{new_images.size} new source images to process"

    # 启动线程池
    @worker_pool.start

    # 并行处理图片
    new_images.each do |full_path|
      @worker_pool.add_job do
        process_single_source(full_path, source_path)
      end
    end

    # 等待所有任务完成
    @worker_pool.stop

    # 批量插入剩余数据
    flush_source_batch

    puts "[SOURCE] Source file indexing completed"
  end

  def process_single_source(full_path, source_path = nil)
    source_path ||= @project.source_path.strip
    relative_path = Pathname.new(full_path).relative_path_from(Pathname.new(source_path)).to_s

    img = nil
    comparator = nil

    begin
      # 读取图片信息
      img = Magick::Image.ping(full_path).first
      width = img.columns
      height = img.rows
      size = File.size(full_path)

      # 立即释放 ping 的图片对象
      img.destroy!
      img = nil

      # 计算哈希值
      comparator = ImageComparator.new(full_path)

      # 准备记录数据
      record = {
        project_id: @project.id,
        relative_path: relative_path,
        full_path: full_path,
        width: width,
        height: height,
        size_bytes: size,
        aspect_ratio: width.to_f / height,
        area: width * height,
        phash: comparator.phash.to_s,
        ahash: comparator.ahash.to_s,
        dhash: comparator.dhash.to_s,
        histogram: comparator.histogram.to_json,
        status: 'indexed',
        created_at: Time.now,
        updated_at: Time.now
      }

      # 线程安全地添加到批次
      @mutex.synchronize do
        @source_batch << record

        # 当批次达到阈值时，批量插入
        if @source_batch.size >= BATCH_SIZE
          flush_source_batch
        end
      end

      puts "Processed source: #{relative_path}"
    rescue => e
      puts "Error processing source #{full_path}: #{e.message}"
    ensure
      # 及时释放所有图片对象引用
      if img
        img.destroy!
        img = nil
      end
      comparator = nil
    end
  end

  def flush_source_batch
    return if @source_batch.empty?

    batch = @source_batch.dup
    @source_batch.clear

    begin
      SourceFile.insert_all(batch)
      puts "Batch inserted #{batch.size} source files"
    rescue => e
      puts "Error batch inserting source files: #{e.message}"
    end
  end

  def index_target_files
    puts "\n[TARGET] Starting target file indexing..."

    @project.project_targets.each do |target|
      puts "\n[TARGET] Processing target: #{target.name}"
      puts "[TARGET] Target path: #{target.path}"

      # 检查路径是否存在
      unless Dir.exist?(target.path)
        puts "[ERROR] Target path does not exist: #{target.path}"
        next
      end

      images = Dir.glob(File.join(target.path, "**", "*.{jpg,jpeg,png,webp,bmp}"), File::FNM_CASEFOLD)

      puts "[TARGET] Found #{images.size} target images in #{target.name}"

      if images.empty?
        puts "[WARNING] No target images found in #{target.name}!"
        puts "[WARNING] Path: #{target.path}"
        puts "[WARNING] Sample files: #{Dir.glob(File.join(target.path, '*')).first(5).join(', ')}"
      end

      # 批量检查已存在的文件
      existing_paths = TargetFile.where(project_target: target)
                                 .pluck(:relative_path)
                                 .to_set

      # 过滤掉已存在的文件
      new_images = images.reject do |full_path|
        relative_path = Pathname.new(full_path).relative_path_from(Pathname.new(target.path)).to_s
        existing_paths.include?(relative_path)
      end

      puts "[TARGET] #{new_images.size} new target images to process for #{target.name}"

      # 初始化该 target 的批次数组
      @target_batches[target.id] = []

      # 启动线程池（重新启动）
      @worker_pool.start

      # 并行处理图片
      new_images.each do |full_path|
        @worker_pool.add_job do
          process_single_target(target, full_path)
        end
      end

      # 等待所有任务完成
      @worker_pool.stop

      # 批量插入剩余数据
      flush_target_batch(target.id)

      puts "[TARGET] Target #{target.name} indexing completed"
    end

    puts "\n[TARGET] All target files indexed"
  end

  def process_single_target(target, full_path)
    relative_path = Pathname.new(full_path).relative_path_from(Pathname.new(target.path)).to_s

    img = nil
    comparator = nil

    begin
      # 读取图片信息
      img = Magick::Image.ping(full_path).first
      width = img.columns
      height = img.rows
      size = File.size(full_path)

      # 立即释放 ping 的图片对象
      img.destroy!
      img = nil

      # 计算哈希值
      comparator = ImageComparator.new(full_path)

      # 准备记录数据
      record = {
        project_target_id: target.id,
        relative_path: relative_path,
        full_path: full_path,
        width: width,
        height: height,
        size_bytes: size,
        aspect_ratio: width.to_f / height,
        area: width * height,
        phash: comparator.phash.to_s,
        ahash: comparator.ahash.to_s,
        dhash: comparator.dhash.to_s,
        histogram: comparator.histogram.to_json,
        created_at: Time.now,
        updated_at: Time.now
      }

      # 线程安全地添加到批次
      @mutex.synchronize do
        @target_batches[target.id] ||= []
        @target_batches[target.id] << record

        # 当批次达到阈值时，批量插入
        if @target_batches[target.id].size >= BATCH_SIZE
          flush_target_batch(target.id)
        end
      end

      puts "Processed target: #{relative_path}"
    rescue => e
      puts "Error processing target #{full_path}: #{e.message}"
    ensure
      # 及时释放所有图片对象引用
      if img
        img.destroy!
        img = nil
      end
      comparator = nil
    end
  end

  def flush_target_batch(target_id)
    return unless @target_batches[target_id]&.any?

    batch = @target_batches[target_id].dup
    @target_batches[target_id].clear

    begin
      TargetFile.insert_all(batch)
      puts "Batch inserted #{batch.size} target files for target #{target_id}"
    rescue => e
      puts "Error batch inserting target files: #{e.message}"
    end
  end
end
