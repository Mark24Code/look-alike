class DimensionFilter
  # 渐进式容差配置：从严格到宽松
  TOLERANCE_LEVELS = [
    { aspect_ratio: 0.1, area_min: 0.5, area_max: 2.0 },   # 10%, 50%-200%
    { aspect_ratio: 0.15, area_min: 0.4, area_max: 2.5 },  # 15%, 40%-250%
    { aspect_ratio: 0.20, area_min: 0.3, area_max: 3.0 },  # 20%, 30%-300%
    { aspect_ratio: 0.30, area_min: 0.2, area_max: 4.0 },  # 30%, 20%-400%
  ].freeze

  def self.filter_targets(source_file, target_files)
    return target_files if target_files.empty?

    source_ratio = source_file.aspect_ratio
    source_area = source_file.area

    return target_files unless source_ratio && source_area

    # 尝试使用默认容差（第一级）
    filter_targets_with_tolerance(source_file, target_files, TOLERANCE_LEVELS[0])
  end

  # 使用指定容差进行筛选
  def self.filter_targets_with_tolerance(source_file, target_files, tolerance_config)
    return target_files if target_files.empty?

    source_ratio = source_file.aspect_ratio
    source_area = source_file.area

    return target_files unless source_ratio && source_area

    aspect_tolerance = tolerance_config[:aspect_ratio]
    area_min_ratio = tolerance_config[:area_min]
    area_max_ratio = tolerance_config[:area_max]

    # 宽高比范围
    ratio_min = source_ratio * (1 - aspect_tolerance)
    ratio_max = source_ratio * (1 + aspect_tolerance)

    # 面积范围
    area_min = (source_area * area_min_ratio).to_i
    area_max = (source_area * area_max_ratio).to_i

    # 筛选
    target_files.select do |tf|
      tf.aspect_ratio && tf.area &&
      tf.aspect_ratio >= ratio_min &&
      tf.aspect_ratio <= ratio_max &&
      tf.area >= area_min &&
      tf.area <= area_max
    end
  end

  # 自适应筛选：逐级放宽条件直到找到候选项
  def self.adaptive_filter_targets(source_file, target_files)
    return target_files if target_files.empty?

    source_ratio = source_file.aspect_ratio
    source_area = source_file.area

    return target_files unless source_ratio && source_area

    # 尝试每个容差级别
    TOLERANCE_LEVELS.each_with_index do |tolerance_config, index|
      filtered = filter_targets_with_tolerance(source_file, target_files, tolerance_config)

      if filtered.any?
        puts "  自适应筛选: 使用容差级别 #{index + 1} (宽高比±#{(tolerance_config[:aspect_ratio] * 100).round}%, 面积#{(tolerance_config[:area_min] * 100).round}%-#{(tolerance_config[:area_max] * 100).round}%), 找到 #{filtered.size} 个候选"
        return filtered
      end
    end

    # 所有容差级别都失败，返回所有target_files
    puts "  自适应筛选: 所有容差级别均无结果，返回全部 #{target_files.size} 个目标"
    target_files
  end
end
