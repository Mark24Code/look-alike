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
    @project.update(status: 'processing', started_at: Time.now)

    begin
      # 第一轮：索引（如果未完成）
      unless ['indexed', 'comparing', 'completed'].include?(@project.status)
        puts "Starting indexing phase..."
        IndexingService.new(@project).process
        puts "Indexing phase completed"
      end

      # 第二轮：匹配
      @project.update(status: 'comparing')
      puts "Starting comparison phase..."

      @worker_pool.start

      # 并行处理source文件
      source_files = @project.source_files.where(status: 'indexed').to_a
      puts "Comparing #{source_files.size} source files..."

      source_files.each do |sf|
        @worker_pool.add_job do
          compare_single_source(sf)
        end
      end

      @worker_pool.stop

      # 批量插入剩余的候选项
      flush_candidate_batch

      # 批量更新剩余的 source_files 状态
      flush_update_batch

      # 自动创建默认选择（选择所有 rank=1 的候选项）
      create_auto_selections

      @project.update(status: 'completed', ended_at: Time.now)
      puts "Comparison phase completed"
    rescue => e
      @project.update(status: 'error', error_message: e.message)
      puts "ComparisonService error: #{e.message}"
      puts e.backtrace
    ensure
      @worker_pool&.stop
    end
  end

  private

  def compare_single_source(source_file)
    @project.project_targets.each do |target|
      # 获取所有target文件（避免 N+1 查询，在外层已经 includes）
      all_targets = target.target_files.to_a

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
          # 限制最多20个候选项
          final_candidates = filtered.first(20)
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
          project_target_id: target.id,
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

      puts "Found #{final_candidates.size} candidates for #{source_file.relative_path} in #{target.name} (threshold: #{used_threshold}%)"

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
