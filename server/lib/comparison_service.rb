require_relative 'worker_pool'
require_relative 'indexing_service'
require_relative 'dimension_filter'
require_relative 'image_comparator'

class ComparisonService
  BATCH_SIZE = 100  # 每批次插入100条记录

  def initialize(project)
    @project = project
    @worker_pool = WorkerPool.new(4)
    @candidate_batch = []
    @update_batch = []
    @mutex = Mutex.new
  end

  def process
    puts "\n========================================="
    puts "ComparisonService.process started for project #{@project.id}: #{@project.name}"
    puts "Project status: #{@project.status}"
    puts "========================================="

    @project.update(status: 'processing', started_at: Time.now)

    begin
      # 第一轮：索引（必须完成）
      # 只有当状态是 'indexed' 时才能跳过索引
      if @project.status != 'indexed'
        puts "\n[INDEXING] Starting indexing phase..."
        IndexingService.new(@project).process
        puts "[INDEXING] Indexing phase completed"
      else
        puts "[INDEXING] Project already indexed, skipping indexing phase"
      end

      # 验证索引是否完成
      total_source_files = @project.source_files.count
      indexed_source_files = @project.source_files.where(status: 'indexed').count
      total_target_files = TargetFile.joins(:project_target).where(project_targets: { project_id: @project.id }).count

      puts "\n[VALIDATION] Validating indexing results..."
      puts "[VALIDATION] Total source files: #{total_source_files}"
      puts "[VALIDATION] Indexed source files: #{indexed_source_files}"
      puts "[VALIDATION] Total target files: #{total_target_files}"

      # 检查是否有未索引的源文件
      if total_source_files > 0 && indexed_source_files < total_source_files
        puts "[WARNING] Not all source files are indexed! #{indexed_source_files}/#{total_source_files}"
        puts "[WARNING] Waiting for indexing to complete..."
        # 不应该继续，因为索引应该已经完成了
      end

      # 如果没有源文件，报错
      if total_source_files == 0
        error_msg = "No source files found after indexing. Please check source_path: #{@project.source_path}"
        puts "[ERROR] #{error_msg}"
        @project.update(status: 'error', error_message: error_msg)
        return
      end

      # 如果没有目标文件，报错
      if total_target_files == 0
        error_msg = "No target files found after indexing. Please check target paths."
        puts "[ERROR] #{error_msg}"
        @project.update(status: 'error', error_message: error_msg)
        return
      end

      # 第二轮：比较（只有索引完成后才能开始）
      puts "\n[COMPARING] All files indexed, starting comparison phase..."
      @project.update(status: 'comparing')

      # 预加载所有需要的数据到内存，避免在多线程中查询数据库
      puts "[COMPARING] Preloading project targets and target files..."
      project_targets_data = ProjectTarget.where(project_id: @project.id)
                                          .includes(:target_files)
                                          .map do |target|
        {
          id: target.id,
          name: target.name,
          target_files: target.target_files.to_a
        }
      end
      puts "[COMPARING] Preloaded #{project_targets_data.size} targets"

      @worker_pool.start

      # 只处理已索引的source文件
      source_files = @project.source_files.where(status: 'indexed').to_a
      puts "[COMPARING] Processing #{source_files.size} indexed source files..."

      if source_files.empty?
        puts "[ERROR] No indexed source files found! Cannot proceed with comparison."
        @project.update(status: 'error', error_message: 'No indexed source files')
        return
      end

      source_files.each do |sf|
        @worker_pool.add_job do
          compare_single_source(sf, project_targets_data)
        end
      end

      @worker_pool.stop

      # 批量插入剩余的候选项
      flush_candidate_batch

      # 批量更新剩余的 source_files 状态
      flush_update_batch

      # 统计生成的候选项
      candidate_count = ComparisonCandidate.joins("INNER JOIN source_files ON source_files.id = comparison_candidates.source_file_id")
                                           .where("source_files.project_id = ?", @project.id)
                                           .count
      puts "\n[STATS] Generated #{candidate_count} comparison candidates"

      # 自动创建默认选择（选择所有 rank=1 的候选项）
      create_auto_selections

      @project.update(status: 'completed', ended_at: Time.now)
      puts "\n[SUCCESS] Comparison phase completed"
      puts "========================================="
    rescue => e
      @project.update(status: 'error', error_message: e.message)
      puts "\n[ERROR] ComparisonService error: #{e.message}"
      puts "[ERROR] Backtrace:"
      puts e.backtrace.join("\n")
      puts "========================================="
    ensure
      @worker_pool&.stop
    end
  end

  private

  def compare_single_source(source_file, project_targets_data)
    # 使用预加载的数据，避免在线程中访问 ActiveRecord 关联
    project_targets_data.each do |target_data|
      target_id = target_data[:id]
      target_name = target_data[:name]
      all_targets = target_data[:target_files]

      # 第一步：自适应尺寸筛选
      filtered_targets = DimensionFilter.adaptive_filter_targets(source_file, all_targets)

      puts "Source #{source_file.relative_path}: #{all_targets.size} targets -> #{filtered_targets.size} after adaptive dimension filter"

      # 第二步：哈希比较，使用自适应阈值
      candidates = []

      filtered_targets.each do |tf|
        begin
          # 使用预计算的哈希值
          similarity = calculate_similarity_from_hashes(source_file, tf)

          # 先收集所有相似度数据
          candidates << {
            target_file: tf,
            similarity: similarity
          }
        rescue => e
          puts "Error comparing with target #{tf.id}: #{e.message}"
          next
        end
      end

      # 排序
      candidates.sort_by! { |c| -c[:similarity] }

      # 自适应阈值策略：确保至少有一个候选项
      similarity_thresholds = [50.0, 40.0, 30.0, 20.0, 10.0, 0.0]
      final_candidates = []
      used_threshold = 50.0

      similarity_thresholds.each do |threshold|
        filtered = candidates.select { |c| c[:similarity] > threshold }

        if filtered.any?
          # 限制最多50个候选项
          final_candidates = filtered.first(50)
          used_threshold = threshold
          break
        end
      end

      # 如果所有阈值都没有结果，强制选择相似度最高的1个
      if final_candidates.empty? && candidates.any?
        final_candidates = [candidates.first]
        used_threshold = 0.0
        puts "  强制选择最高相似度候选项: #{candidates.first[:similarity].round(2)}%"
      end

      # 准备批量插入数据
      final_candidates.each_with_index do |cand, index|
        record = {
          source_file_id: source_file.id,
          project_target_id: target_id,
          file_path: cand[:target_file].full_path,
          similarity_score: cand[:similarity],
          rank: index + 1,
          width: cand[:target_file].width,
          height: cand[:target_file].height
        }

        # 线程安全地添加到批次
        @mutex.synchronize do
          @candidate_batch << record

          # 当批次达到阈值时，批量插入
          if @candidate_batch.size >= BATCH_SIZE
            flush_candidate_batch
          end
        end
      end

      puts "Found #{final_candidates.size} candidates for #{source_file.relative_path} in #{target_name} (threshold: #{used_threshold}%)"

      # 及时释放 candidates 数组的内存引用
      candidates = nil
      all_targets = nil
      filtered_targets = nil
    end

    # 标记为已分析（收集到批次中稍后批量更新）
    @mutex.synchronize do
      @update_batch << source_file.id

      if @update_batch.size >= BATCH_SIZE
        flush_update_batch
      end
    end
  rescue => e
    puts "Error comparing source #{source_file.id}: #{e.message}"
    puts e.backtrace
  end

  # 批量插入候选项
  def flush_candidate_batch
    return if @candidate_batch.empty?

    batch = @candidate_batch.dup
    @candidate_batch.clear

    begin
      ComparisonCandidate.insert_all(batch)
      puts "Batch inserted #{batch.size} comparison candidates"
    rescue => e
      puts "Error batch inserting candidates: #{e.message}"
    end
  end

  # 批量更新 source_files 状态
  def flush_update_batch
    return if @update_batch.empty?

    batch = @update_batch.dup
    @update_batch.clear

    begin
      SourceFile.where(id: batch).update_all(status: 'analyzed')
      puts "Batch updated #{batch.size} source files to analyzed"
    rescue => e
      puts "Error batch updating source files: #{e.message}"
    end
  end

  # 自动创建默认选择：为每个 source_file + target 组合选择 rank=1 的候选项
  def create_auto_selections
    puts "Creating auto-selections for best matches..."

    # 获取所有 rank=1 的候选项
    best_candidates = ComparisonCandidate
      .where(rank: 1)
      .joins("INNER JOIN source_files ON source_files.id = comparison_candidates.source_file_id")
      .where("source_files.project_id = ?", @project.id)
      .select(:id, :source_file_id, :project_target_id)

    # 批量创建 TargetSelection 记录
    selections = []
    best_candidates.each do |candidate|
      selections << {
        source_file_id: candidate.source_file_id,
        project_target_id: candidate.project_target_id,
        selected_candidate_id: candidate.id,
        no_match: false,
        created_at: Time.now,
        updated_at: Time.now
      }

      # 批量插入
      if selections.size >= BATCH_SIZE
        TargetSelection.insert_all(selections)
        puts "Batch inserted #{selections.size} auto-selections"
        selections.clear
      end
    end

    # 插入剩余的选择记录
    if selections.any?
      TargetSelection.insert_all(selections)
      puts "Inserted final #{selections.size} auto-selections"
    end

    puts "Auto-selection completed"
  end

  # 使用预计算的哈希值计算相似度
  def calculate_similarity_from_hashes(source, target)
    # Convert string hashes back to integers for comparison
    phash_sim = ImageComparator.hash_similarity(source.phash.to_i, target.phash.to_i, 64)
    ahash_sim = ImageComparator.hash_similarity(source.ahash.to_i, target.ahash.to_i, 1024)
    dhash_sim = ImageComparator.hash_similarity(source.dhash.to_i, target.dhash.to_i, 64)

    source_hist = JSON.parse(source.histogram)
    target_hist = JSON.parse(target.histogram)
    histogram_sim = ImageComparator.histogram_similarity(source_hist, target_hist)

    # 加权平均
    weights = ImageComparator::WEIGHTS
    phash_sim * weights[:phash] +
    ahash_sim * weights[:ahash] +
    dhash_sim * weights[:dhash] +
    histogram_sim * weights[:histogram]
  end
end
