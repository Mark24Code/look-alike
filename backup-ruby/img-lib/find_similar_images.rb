#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'rmagick'
require 'fileutils'
require 'json'
require 'logger'
require_relative 'compare_images'

# 日志管理类
class MatchingLogger
  def initialize(log_file_path)
    @file_logger = Logger.new(log_file_path)
    @file_logger.level = Logger::INFO
    @file_logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
  end

  def info(msg)
    @file_logger.info(msg)
  end

  def warn(msg)
    @file_logger.warn(msg)
    puts "  警告: #{msg}"  # 同时输出到控制台
  end

  def error(msg)
    @file_logger.error(msg)
    puts "  错误: #{msg}"  # 同时输出到控制台
  end

  def source_image_start(source_path, index, total)
    msg = "=" * 60
    @file_logger.info(msg)
    @file_logger.info("处理源图片 [#{index}/#{total}]: #{source_path}")
  end

  def matching_result(matches, final_threshold)
    if matches.empty?
      @file_logger.warn("最终结果: 未找到匹配")
    else
      match = matches.first
      @file_logger.info("最终结果: 找到匹配")
      @file_logger.info("  → 目标图片: #{match[:path]}")
      @file_logger.info("  → 相似度: #{match[:similarity].round(2)}%")
      @file_logger.info("  → 最终阈值: #{final_threshold.round(2)}%")
    end
  end

  def log_file_path
    @file_logger.instance_variable_get(:@logdev).filename
  end
end

# 图片元数据类 - 用于快速筛选
class ImageMetadata
  attr_reader :path, :file_size, :width, :height, :format

  def initialize(path)
    @path = path
    @file_size = File.size(path)

    begin
      img = Magick::Image.read(path).first
      @width = img.columns
      @height = img.rows
      @format = img.format
      img.destroy!
    rescue => e
      @width = nil
      @height = nil
      @format = nil
    end
  end

  def valid?
    !@width.nil? && !@height.nil?
  end

  # 判断尺寸是否在冗余范围内 (±10%)
  def size_matches?(other, tolerance = 0.1)
    return false unless valid? && other.valid?

    width_ratio = (@width.to_f / other.width).abs
    height_ratio = (@height.to_f / other.height).abs

    (1 - tolerance) <= width_ratio && width_ratio <= (1 + tolerance) &&
    (1 - tolerance) <= height_ratio && height_ratio <= (1 + tolerance)
  end

  # 判断文件大小是否在冗余范围内 (±10%)
  def file_size_matches?(other, tolerance = 0.1)
    ratio = (@file_size.to_f / other.file_size).abs
    (1 - tolerance) <= ratio && ratio <= (1 + tolerance)
  end

  # 计算与另一张图片的距离评分（用于选择最佳匹配）
  # 返回值越小越接近
  def distance_score(other)
    return Float::INFINITY unless valid? && other.valid?

    # 尺寸差异（归一化）
    width_diff = (@width - other.width).abs.to_f / [@width, other.width].max
    height_diff = (@height - other.height).abs.to_f / [@height, other.height].max

    # 文件大小差异（归一化）
    size_diff = (@file_size - other.file_size).abs.to_f / [@file_size, other.file_size].max

    # 综合评分
    width_diff + height_diff + size_diff
  end
end

# 相似图片查找器
class SimilarImageFinder
  SUPPORTED_FORMATS = %w[.png .jpg .jpeg .webp .gif .bmp .tiff .tif].freeze
  DEFAULT_SIMILARITY_THRESHOLD = 85.0
  TOLERANCE = 0.1

  attr_reader :similarity_threshold

  def initialize(source_dir, target_dir, output_dir, similarity_threshold = DEFAULT_SIMILARITY_THRESHOLD)
    @source_dir = File.expand_path(source_dir)
    @target_dir = File.expand_path(target_dir)
    @output_dir = File.expand_path(output_dir)
    @similarity_threshold = similarity_threshold.to_f
    @source_images_map = {}  # 存储源图片的元数据，用于第二轮处理

    validate_directories!
    validate_similarity_threshold!

    # 创建日志文件
    log_dir = File.join(@output_dir, 'logs')
    FileUtils.mkdir_p(log_dir)
    log_file = File.join(log_dir, "matching_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
    @logger = MatchingLogger.new(log_file)

    puts "日志文件: #{log_file}"
  end

  def find_all_similar_images
    puts "=" * 60
    puts "图片相似度批量查找工具 (完整性优化版)"
    puts "=" * 60
    puts ""
    puts "源目录: #{@source_dir}"
    puts "目标目录: #{@target_dir}"
    puts "输出目录: #{@output_dir}"
    puts "初始相似度阈值: #{@similarity_threshold}%"
    puts ""

    # 收集图片
    puts "正在扫描目录..."
    source_images = collect_images(@source_dir)
    target_images = collect_images(@target_dir)

    puts "找到 #{source_images.size} 张源图片"
    puts "找到 #{target_images.size} 张目标图片"
    puts ""

    if source_images.empty?
      puts "错误: 源目录中没有找到图片文件"
      return
    end

    if target_images.empty?
      puts "错误: 目标目录中没有找到图片文件"
      return
    end

    # 创建输出目录
    FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)

    @logger.info("开始批量匹配: #{source_images.size} 张源图片")

    # 统计信息
    stats = {
      processed: 0,
      matched: 0,
      forced_match: 0,  # 新增：强制匹配数（低于阈值的）
      copied: 0,
      errors: 0
    }

    # 第一轮: 处理每张源图片，使用自适应阈值找到最佳匹配
    puts "=" * 60
    puts "第一轮处理: 自适应阈值匹配"
    puts "=" * 60

    source_images.each_with_index do |source_path, index|
      begin
        puts "\n[#{index + 1}/#{source_images.size}] 处理: #{relative_path(source_path, @source_dir)}"

        matches = find_similar_for_image(source_path, target_images, index + 1, source_images.size)

        if matches.empty?
          puts "  ✗ 未找到匹配（异常情况）"
          @logger.error("源图片未匹配: #{relative_path(source_path, @source_dir)}")
        else
          match = matches.first
          similarity = match[:similarity]

          # 判断是否为强制匹配
          if similarity < @similarity_threshold
            puts "  ⚠ 强制匹配（相似度低于阈值）: #{similarity.round(2)}%"
            stats[:forced_match] += 1
          else
            puts "  ✓ 正常匹配: #{similarity.round(2)}%"
          end

          # 自适应算法保证只返回一个最佳匹配
          copy_single_match(source_path, match)
          stats[:matched] += 1
          stats[:copied] += 1
        end

        stats[:processed] += 1
      rescue => e
        puts "  ✗ 错误: #{e.message}"
        @logger.error("处理失败: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
        stats[:errors] += 1
      end
    end

    # 第一轮统计报告
    print_round1_summary(stats)

    # 第二轮: 格式转换和重命名
    puts "\n" + "=" * 60
    puts "第二轮处理: 格式转换和重命名"
    puts "=" * 60

    rename_stats = rename_to_source_format(source_images)

    # 最终统计报告
    print_final_summary(stats, rename_stats)

    @logger.info("批量匹配完成")
  end

  private

  def validate_directories!
    raise "源目录不存在: #{@source_dir}" unless Dir.exist?(@source_dir)
    raise "目标目录不存在: #{@target_dir}" unless Dir.exist?(@target_dir)
  end

  def validate_similarity_threshold!
    if @similarity_threshold < 0 || @similarity_threshold > 100
      raise "相似度阈值必须在 0-100 之间，当前值: #{@similarity_threshold}"
    end
  end

  # 收集目录中的所有图片文件
  def collect_images(dir)
    images = []

    Dir.glob(File.join(dir, '**', '*')).each do |file|
      next unless File.file?(file)
      next unless SUPPORTED_FORMATS.include?(File.extname(file).downcase)
      images << file
    end

    images
  end

  # 查找与源图片相似的目标图片（使用自适应阈值）
  def find_similar_for_image(source_path, target_paths, index, total)
    rel_path = relative_path(source_path, @source_dir)
    @logger.source_image_start(rel_path, index, total)

    source_meta = ImageMetadata.new(source_path)

    # 保存源图片元数据，用于第二轮处理
    @source_images_map[rel_path] = source_meta

    unless source_meta.valid?
      @logger.error("无法读取图片元数据")
      return []
    end

    # 渐进式快速筛选
    filter_result = progressive_quick_filter(source_meta, target_paths)
    candidates = filter_result[:candidates]
    tolerance = filter_result[:tolerance]

    if tolerance
      puts "  快速筛选: #{target_paths.size} -> #{candidates.size} 张候选图片 (容差: ±#{(tolerance * 100).round}%)"
    else
      puts "  快速筛选: 对所有 #{candidates.size} 张目标图片进行相似度计算"
    end

    if candidates.empty?
      @logger.error("快速筛选后没有候选图片（理论上不应该发生）")
      return []
    end

    # 自适应阈值匹配
    result = adaptive_threshold_matching(source_path, candidates)
    @logger.matching_result(result[:matches], result[:final_threshold])

    if result[:matches].empty?
      puts "  未找到相似图片"
    else
      puts "  自适应阈值: #{result[:final_threshold].round(2)}%"
      puts "  最终匹配: 1 张图片"
      puts "    - #{File.basename(result[:matches].first[:path])} (相似度: #{result[:matches].first[:similarity].round(2)}%)"
    end

    result[:matches]
  end

  # 自适应阈值匹配算法
  def adaptive_threshold_matching(source_path, candidates)
    initial_threshold = @similarity_threshold
    current_threshold = initial_threshold

    # 配置
    step_up = 2.0         # 提高阈值的步长
    step_down = 5.0       # 降低阈值的步长
    min_threshold = 50.0  # 最低阈值
    max_threshold = 100.0 # 最高阈值

    puts "  开始自适应匹配 (初始阈值: #{initial_threshold}%)..."

    # 计算所有候选图片的相似度
    source_comparator = ImageComparator.new(source_path)
    all_matches = []

    candidates.each do |candidate_path|
      begin
        target_comparator = ImageComparator.new(candidate_path)
        similarity = ImageComparator.quick_compare(source_comparator, target_comparator)

        all_matches << {
          path: candidate_path,
          similarity: similarity
        }
      rescue => e
        # 忽略无法处理的图片
      end
    end

    # 按相似度降序排序
    all_matches.sort_by! { |m| -m[:similarity] }

    # 自适应策略
    loop do
      # 筛选当前阈值下的匹配
      current_matches = all_matches.select { |m| m[:similarity] >= current_threshold }

      puts "    阈值 #{current_threshold.round(1)}%: #{current_matches.size} 个匹配"

      case current_matches.size
      when 0
        # 没有匹配，降低阈值
        if current_threshold <= min_threshold
          # 已经到最低阈值，强制选择相似度最高的候选图片
          if all_matches.any?
            best_match = all_matches.first  # 已按相似度降序排序
            @logger.warn("已达最低阈值 (#{min_threshold}%)，强制匹配相似度最高的候选图片")
            @logger.warn("  → 最佳候选: #{File.basename(best_match[:path])}")
            @logger.warn("  → 相似度: #{best_match[:similarity].round(2)}% (低于阈值)")
            puts "    → 强制匹配: #{File.basename(best_match[:path])} (相似度: #{best_match[:similarity].round(2)}%)"
            return { matches: [best_match], final_threshold: best_match[:similarity] }
          else
            # 理论上不应该到这里（因为 progressive_quick_filter 保证了有候选）
            @logger.error("没有任何候选图片，无法匹配")
            puts "    → 错误: 没有任何候选图片"
            return { matches: [], final_threshold: current_threshold }
          end
        end

        # 降低阈值
        current_threshold -= step_down
        current_threshold = [current_threshold, min_threshold].max
        puts "    → 降低阈值"

      when 1
        # 完美：只有一个匹配
        puts "    → 找到唯一最佳匹配 ✓"
        return { matches: current_matches, final_threshold: current_threshold }

      else
        # 多个匹配，尝试提高阈值
        if current_threshold >= max_threshold
          # 已经到最高阈值，选择相似度最高的
          puts "    → 已达最高阈值，选择相似度最高的"
          return { matches: [current_matches.first], final_threshold: current_threshold }
        end

        # 尝试提高阈值
        next_threshold = current_threshold + step_up

        # 预测提高阈值后的匹配数
        next_matches = all_matches.select { |m| m[:similarity] >= next_threshold }

        if next_matches.size == 0
          # 提高后会没有匹配，那就保持当前阈值，选择最高的
          puts "    → 提高阈值会失去所有匹配，选择当前最高相似度"
          return { matches: [current_matches.first], final_threshold: current_threshold }
        elsif next_matches.size == 1
          # 提高后正好一个，完美
          current_threshold = next_threshold
          puts "    → 提高阈值"
        else
          # 提高后还是多个，继续提高
          current_threshold = next_threshold
          puts "    → 提高阈值"
        end
      end

      # 防止无限循环
      if current_threshold >= max_threshold
        current_matches = all_matches.select { |m| m[:similarity] >= current_threshold }
        if current_matches.empty?
          current_matches = [all_matches.first] if all_matches.any?
        end
        puts "    → 达到最高阈值，选择最佳匹配"
        return { matches: [current_matches.first], final_threshold: current_threshold }
      end
    end
  end

  # 渐进式快速筛选: 逐步放宽容差，确保有候选图片
  def progressive_quick_filter(source_meta, target_paths)
    tolerances = [0.1, 0.15, 0.20, 0.30]  # 10%, 15%, 20%, 30%

    tolerances.each do |tolerance|
      candidates = []

      target_paths.each do |target_path|
        target_meta = ImageMetadata.new(target_path)

        next unless target_meta.valid?
        next unless source_meta.file_size_matches?(target_meta, tolerance)
        next unless source_meta.size_matches?(target_meta, tolerance)

        candidates << target_path
      end

      if candidates.any?
        @logger.info("快速筛选成功: 使用容差 ±#{(tolerance * 100).round}%, 找到 #{candidates.size} 个候选")
        return { candidates: candidates, tolerance: tolerance }
      end

      @logger.info("快速筛选失败: 容差 ±#{(tolerance * 100).round}%, 无候选图片，尝试放宽...")
    end

    # 所有容差都失败，返回所有 target_paths（完全不筛选）
    @logger.warn("快速筛选完全失败，将对所有 #{target_paths.size} 张目标图片进行相似度计算")
    { candidates: target_paths, tolerance: nil }
  end

  # 复制单个匹配图片到输出目录
  def copy_single_match(source_path, match)
    # 获取源图片的相对路径
    rel_path = relative_path(source_path, @source_dir)
    rel_dir = File.dirname(rel_path)
    source_basename = File.basename(source_path, '.*')
    target_ext = File.extname(match[:path])

    # 创建输出子目录
    output_subdir = File.join(@output_dir, rel_dir)
    FileUtils.mkdir_p(output_subdir)

    # 临时文件名（后续会重命名）
    temp_filename = "#{source_basename}#{target_ext}"
    output_path = File.join(output_subdir, temp_filename)

    FileUtils.cp(match[:path], output_path)
  end

  # 第二轮：重命名和格式转换
  def rename_to_source_format(source_images)
    stats = {
      checked: 0,
      converted: 0,
      renamed: 0,
      missing: 0
    }

    puts "\n正在处理格式转换和重命名..."

    source_images.each do |source_path|
      rel_path = relative_path(source_path, @source_dir)
      source_basename = File.basename(source_path, '.*')
      source_ext = File.extname(source_path)
      rel_dir = File.dirname(rel_path)

      # 查找输出目录中对应的文件
      output_subdir = File.join(@output_dir, rel_dir)

      # 可能的临时文件（各种扩展名）
      possible_files = Dir.glob(File.join(output_subdir, "#{source_basename}.*"))

      stats[:checked] += 1

      if possible_files.empty?
        stats[:missing] += 1
        next
      end

      current_file = possible_files.first
      current_ext = File.extname(current_file)

      # 目标文件
      target_file = File.join(output_subdir, "#{source_basename}#{source_ext}")

      if current_ext == source_ext
        # 格式已经正确，可能只需要重命名
        if current_file != target_file
          File.rename(current_file, target_file)
          stats[:renamed] += 1
        end
      else
        # 需要格式转换
        begin
          img = Magick::Image.read(current_file).first
          img.format = source_ext.sub('.', '').upcase
          img.write(target_file)
          img.destroy!

          # 删除原文件
          File.delete(current_file) if File.exist?(current_file) && current_file != target_file

          stats[:converted] += 1
        rescue => e
          puts "  警告: #{rel_path} 格式转换失败，保留原格式"
          if current_file != target_file
            # 转换失败，使用原扩展名重命名
            fallback = File.join(output_subdir, "#{source_basename}#{current_ext}")
            File.rename(current_file, fallback) if current_file != fallback
          end
        end
      end
    end

    if stats[:missing] > 0
      puts "\n警告: 有 #{stats[:missing]} 个源文件没有找到匹配"
    end

    stats
  end

  # 复制匹配的图片到输出目录，并在文件名中编码相似度信息
  def copy_matched_images(source_path, matches)
    # 获取源图片的相对路径
    rel_path = relative_path(source_path, @source_dir)
    rel_dir = File.dirname(rel_path)
    source_basename = File.basename(source_path, '.*')
    source_ext = File.extname(source_path)

    # 创建输出子目录
    output_subdir = File.join(@output_dir, rel_dir)
    FileUtils.mkdir_p(output_subdir)

    matches.each do |match|
      target_basename = File.basename(match[:path], '.*')
      target_ext = File.extname(match[:path])

      # 文件名格式: 源文件名_目标文件名_相似度.扩展名
      # 例如: vacation_img001_95.5.jpg
      similarity_str = match[:similarity].round(2).to_s.gsub('.', '_')
      new_filename = "#{source_basename}_#{target_basename}_#{similarity_str}#{target_ext}"
      output_path = File.join(output_subdir, new_filename)

      # 处理文件名冲突（极少发生）
      counter = 1
      while File.exist?(output_path)
        new_filename = "#{source_basename}_#{target_basename}_#{similarity_str}_#{counter}#{target_ext}"
        output_path = File.join(output_subdir, new_filename)
        counter += 1
      end

      FileUtils.cp(match[:path], output_path)
    end
  end

  # 第二轮处理：去重和格式转换
  def deduplicate_output
    stats = {
      groups: 0,
      removed: 0,
      converted: 0,
      kept: 0
    }

    # 按源图片分组输出文件
    groups = group_output_by_source

    if groups.empty?
      puts "\n没有需要处理的文件"
      return stats
    end

    stats[:groups] = groups.size
    puts "\n找到 #{groups.size} 个源图片组"

    groups.each do |source_rel_path, matched_files|
      puts "\n处理组: #{source_rel_path}"
      puts "  找到 #{matched_files.size} 个匹配文件"

      # 选择最优图片
      best_file = select_best_match(source_rel_path, matched_files)

      if best_file
        # 转换格式并重命名
        final_path = rename_to_source_name(source_rel_path, best_file)

        if final_path
          stats[:kept] += 1
          stats[:converted] += 1 if best_file != final_path

          # 删除其他文件
          matched_files.each do |file|
            next if file == best_file || file == final_path
            File.delete(file) if File.exist?(file)
            stats[:removed] += 1
          end

          puts "  ✓ 保留: #{File.basename(final_path)}"
          puts "  ✗ 删除: #{matched_files.size - 1} 个文件" if matched_files.size > 1
        end
      end
    end

    stats
  end

  # 按源图片分组输出目录中的文件
  def group_output_by_source
    groups = {}

    # 先获取所有源图片的相对路径（作为有效的源文件列表）
    valid_sources = @source_images_map.keys

    Dir.glob(File.join(@output_dir, '**', '*')).each do |file|
      next unless File.file?(file)
      next unless SUPPORTED_FORMATS.include?(File.extname(file).downcase)

      # 从文件名解析源图片信息
      # 文件名格式: 源文件名_目标文件名_相似度.扩展名
      basename = File.basename(file)
      rel_dir = Pathname.new(File.dirname(file)).relative_path_from(Pathname.new(@output_dir)).to_s

      # 匹配文件名模式，提取各部分
      # 格式: 任意字符_任意字符_数字_数字.扩展名
      # 需要找到最后一个匹配 _数字_数字 的模式
      if basename =~ /^(.+)_(.+?)_(\d+)_(\d+)(\..+)$/
        # $1 可能包含下划线，需要找到正确的分割点
        # 策略：从后往前找，最后一个 _目标名_相似度 之前的就是源文件名
        full_prefix = $1  # 可能是 "btn_before_18" 这样的
        target_name = $2   # 目标文件名的一部分
        sim1 = $3          # 相似度整数部分
        sim2 = $4          # 相似度小数部分
        ext = $5

        # 反向推断：尝试找到匹配的源文件
        # 遍历有效的源文件列表，看哪个源文件能匹配
        matched_source = nil
        valid_sources.each do |source_rel_path|
          source_dir_part = File.dirname(source_rel_path)
          source_basename = File.basename(source_rel_path, '.*')
          source_ext_part = File.extname(source_rel_path)

          # 检查目录是否匹配
          next unless (rel_dir == '.' && source_dir_part == '.') ||
                      (rel_dir == source_dir_part)

          # 检查文件名是否以源文件名开头
          # 例如 "btn_before_18_100_0.png" 应该匹配源文件 "btn_before.png"
          if basename.start_with?(source_basename + '_')
            matched_source = source_rel_path
            break
          end
        end

        if matched_source
          groups[matched_source] ||= []
          groups[matched_source] << file
        else
          # 无法匹配到有效的源文件，删除此文件（孤立文件）
          puts "  警告: 发现无法匹配的文件，将删除: #{File.basename(file)}"
          File.delete(file) if File.exist?(file)
        end
      end
    end

    groups
  end

  # 选择最优匹配图片
  def select_best_match(source_rel_path, matched_files)
    return nil if matched_files.empty?
    return matched_files.first if matched_files.size == 1

    # 获取源图片路径和元数据
    source_path = File.join(@source_dir, source_rel_path)
    source_meta = @source_images_map[source_rel_path]

    puts "  重新计算相似度（使用多算法加权）..."

    # 重新计算每个文件与源图片的相似度
    begin
      source_comparator = ImageComparator.new(source_path)

      candidates = matched_files.map do |file|
        begin
          # 重新计算相似度（使用多算法加权）
          target_comparator = ImageComparator.new(file)
          similarity = ImageComparator.quick_compare(source_comparator, target_comparator)

          # 读取文件元数据
          meta = ImageMetadata.new(file)

          puts "    - #{File.basename(file)}: #{similarity.round(2)}%"

          {
            path: file,
            similarity: similarity,
            meta: meta
          }
        rescue => e
          # 计算失败，相似度设为0
          puts "    - #{File.basename(file)}: 计算失败"
          {
            path: file,
            similarity: 0.0,
            meta: ImageMetadata.new(file)
          }
        end
      end

      # 按优先级排序
      candidates.sort_by! do |c|
        # 优先级1: 相似度（越高越好，负值用于降序）
        # 优先级2: 距离评分（越小越好）
        distance = source_meta ? source_meta.distance_score(c[:meta]) : 0
        [-c[:similarity], distance]
      end

      candidates.first[:path]
    rescue => e
      # 如果源图片无法读取，返回第一个文件
      puts "    警告: 无法读取源图片，使用第一个匹配文件"
      matched_files.first
    end
  end

  # 重命名为源图片名字，并转换格式（如需要）
  def rename_to_source_name(source_rel_path, selected_file)
    # 获取源图片信息
    source_meta = @source_images_map[source_rel_path]
    source_ext = File.extname(source_rel_path).downcase
    selected_ext = File.extname(selected_file).downcase

    # 构建目标路径
    target_dir = File.dirname(selected_file)
    target_basename = File.basename(source_rel_path, '.*')
    target_path = File.join(target_dir, "#{target_basename}#{source_ext}")

    # 如果格式相同，直接重命名
    if source_ext == selected_ext
      File.rename(selected_file, target_path) unless selected_file == target_path
      return target_path
    end

    # 格式不同，需要转换
    begin
      img = Magick::Image.read(selected_file).first

      # 设置输出格式
      img.format = source_ext.sub('.', '').upcase

      # 写入目标路径
      img.write(target_path)
      img.destroy!

      # 删除原文件
      File.delete(selected_file) if File.exist?(selected_file)

      target_path
    rescue => e
      puts "    警告: 格式转换失败 (#{e.message})，保留原格式"
      # 转换失败，使用原文件名
      fallback_path = File.join(target_dir, "#{target_basename}#{selected_ext}")
      File.rename(selected_file, fallback_path) unless selected_file == fallback_path
      fallback_path
    end
  end

  # 第三轮处理：处理缺失的文件
  def handle_missing_files(source_images)
    stats = {
      checked: 0,
      missing: 0,
      retried: 0,
      found: 0,
      still_missing: 0
    }

    puts "\n检查输出目录完整性..."

    source_images.each do |source_path|
      rel_path = relative_path(source_path, @source_dir)
      source_basename = File.basename(source_path, '.*')
      source_ext = File.extname(source_path)
      rel_dir = File.dirname(rel_path)

      # 检查输出目录中是否有对应文件
      output_subdir = File.join(@output_dir, rel_dir)
      expected_file = File.join(output_subdir, "#{source_basename}#{source_ext}")

      stats[:checked] += 1

      next if File.exist?(expected_file)

      # 文件缺失
      stats[:missing] += 1
      puts "\n缺失文件: #{rel_path}"

      # 尝试在整个目标目录重新查找（放宽条件）
      puts "  尝试重新查找（降低阈值到 #{[@similarity_threshold - 10, 50].max}%）..."

      retry_threshold = [@similarity_threshold - 10, 50].max
      target_images = collect_images(@target_dir)

      # 降低阈值重新查找
      old_threshold = @similarity_threshold
      @similarity_threshold = retry_threshold

      matches = find_similar_for_image(source_path, target_images)
      @similarity_threshold = old_threshold

      if matches.empty?
        puts "  ✗ 仍未找到相似图片"
        stats[:still_missing] += 1
      else
        stats[:retried] += 1
        puts "  ✓ 找到 #{matches.size} 张相似图片（最高相似度: #{matches.first[:similarity].round(2)}%）"

        # 选择最好的一张
        best_match = matches.first

        # 复制到输出目录
        FileUtils.mkdir_p(output_subdir) unless Dir.exist?(output_subdir)

        # 读取并转换格式
        begin
          img = Magick::Image.read(best_match[:path]).first
          img.format = source_ext.sub('.', '').upcase
          img.write(expected_file)
          img.destroy!

          stats[:found] += 1
          puts "  ✓ 已添加: #{File.basename(expected_file)}"
        rescue => e
          # 转换失败，直接复制
          FileUtils.cp(best_match[:path], expected_file)
          stats[:found] += 1
          puts "  ✓ 已复制: #{File.basename(expected_file)} (格式转换失败，保持原格式)"
        end
      end
    end

    if stats[:missing] == 0
      puts "\n所有源文件都有对应的输出文件 ✓"
    end

    stats
  end

  def relative_path(path, base)
    Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
  end

  def print_round1_summary(stats)
    puts ""
    puts "=" * 60
    puts "第一轮处理完成"
    puts "=" * 60
    puts ""
    puts "处理的源图片数: #{stats[:processed]}"
    puts "成功匹配的图片: #{stats[:matched]}"
    puts "  - 正常匹配: #{stats[:matched] - stats[:forced_match]}"
    puts "  - 强制匹配: #{stats[:forced_match]} (低于初始阈值)" if stats[:forced_match] > 0
    puts "未匹配的图片: #{stats[:processed] - stats[:matched]}"
    puts "复制的文件数: #{stats[:copied]}"
    puts "错误数: #{stats[:errors]}"
  end

  def print_final_summary(stats, rename_stats)
    puts ""
    puts "=" * 60
    puts "所有处理完成 - 最终统计"
    puts "=" * 60
    puts ""
    puts "第一轮（自适应阈值匹配）:"
    puts "  处理的源图片数: #{stats[:processed]}"
    puts "  成功匹配的图片: #{stats[:matched]}"
    puts "  - 正常匹配: #{stats[:matched] - stats[:forced_match]}"
    puts "  - 强制匹配: #{stats[:forced_match]} (低于初始阈值)" if stats[:forced_match] > 0
    puts "  未匹配的图片: #{stats[:processed] - stats[:matched]}"
    puts ""
    puts "第二轮（格式转换和重命名）:"
    puts "  检查的文件数: #{rename_stats[:checked]}"
    puts "  转换格式的文件: #{rename_stats[:converted]}"
    puts "  重命名的文件: #{rename_stats[:renamed]}"
    puts "  缺失的文件: #{rename_stats[:missing]}"
    puts ""
    puts "输出目录: #{@output_dir}"

    # 计算输出目录实际文件数
    output_count = collect_images(@output_dir).size
    puts "实际输出文件数: #{output_count} / #{stats[:processed]}"

    if output_count == stats[:processed]
      puts "✓ 成功匹配 #{output_count} 个文件，数量完全一致"
    else
      puts "⚠ 警告: 输出文件数与源文件数不一致"
      puts "  缺失: #{stats[:processed] - output_count} 个文件" if output_count < stats[:processed]
    end

    puts ""
    puts "详细日志: #{@logger.log_file_path}"
    puts "=" * 60
  end
end

# 命令行接口
if __FILE__ == $PROGRAM_NAME
  if ARGV.size < 3 || ARGV.size > 4
    puts "用法: ruby #{File.basename(__FILE__)} <源目录> <目标目录> <输出目录> [相似度阈值]"
    puts ""
    puts "参数说明:"
    puts "  源目录       - 要遍历的图片目录"
    puts "  目标目录     - 在此目录中查找相似图片"
    puts "  输出目录     - 存放找到的相似图片"
    puts "  相似度阈值   - 可选，默认 85 (范围: 0-100)"
    puts ""
    puts "功能说明:"
    puts "  第一轮: 使用自适应阈值匹配算法"
    puts "         - 初始阈值: 默认85%"
    puts "         - 如果匹配多个 → 提高阈值筛选到唯一"
    puts "         - 如果没有匹配 → 降低阈值重新查找"
    puts "         - 确保每个源图片找到最佳的一个匹配"
    puts "  第二轮: 格式转换和重命名"
    puts "         - 自动转换为源图片的格式"
    puts "         - 使用源图片的文件名"
    puts ""
    puts "支持格式:"
    puts "  #{SimilarImageFinder::SUPPORTED_FORMATS.join(', ')}"
    puts ""
    puts "示例:"
    puts "  ruby #{File.basename(__FILE__)} ./source ./target ./output"
    puts "  ruby #{File.basename(__FILE__)} ./source ./target ./output 90"
    exit 1
  end

  source_dir = ARGV[0]
  target_dir = ARGV[1]
  output_dir = ARGV[2]
  similarity_threshold = ARGV[3] ? ARGV[3].to_f : SimilarImageFinder::DEFAULT_SIMILARITY_THRESHOLD

  begin
    finder = SimilarImageFinder.new(source_dir, target_dir, output_dir, similarity_threshold)
    finder.find_all_similar_images
  rescue => e
    puts "错误: #{e.message}"
    puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
    exit 1
  end
end
