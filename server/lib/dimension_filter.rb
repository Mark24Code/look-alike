class DimensionFilter
  ASPECT_RATIO_TOLERANCE = 0.1  # 10%
  AREA_MIN_RATIO = 0.5          # 50%
  AREA_MAX_RATIO = 2.0          # 200%

  def self.filter_targets(source_file, target_files)
    return target_files if target_files.empty?

    source_ratio = source_file.aspect_ratio
    source_area = source_file.area

    return target_files unless source_ratio && source_area

    # 宽高比范围
    ratio_min = source_ratio * (1 - ASPECT_RATIO_TOLERANCE)
    ratio_max = source_ratio * (1 + ASPECT_RATIO_TOLERANCE)

    # 面积范围
    area_min = (source_area * AREA_MIN_RATIO).to_i
    area_max = (source_area * AREA_MAX_RATIO).to_i

    # 筛选
    target_files.select do |tf|
      tf.aspect_ratio && tf.area &&
      tf.aspect_ratio >= ratio_min &&
      tf.aspect_ratio <= ratio_max &&
      tf.area >= area_min &&
      tf.area <= area_max
    end
  end
end
