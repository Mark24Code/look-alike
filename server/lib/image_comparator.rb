#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'rmagick'

# 增强的图片相似度比较工具
# 使用多种算法组合：pHash, aHash, dHash, 直方图
class ImageComparator
  HASH_SIZE = 8  # 哈希大小 8x8 = 64位
  IMG_SIZE = 32  # 预处理图片大小
  HISTOGRAM_BINS = 256  # 直方图分bin数

  # 算法权重配置
  WEIGHTS = {
    phash: 0.40,      # 感知哈希 - 对缩放压缩不敏感
    ahash: 0.20,      # 平均哈希 - 简单快速
    dhash: 0.20,      # 差分哈希 - 对水平变化敏感
    histogram: 0.20   # 直方图 - 对颜色分布敏感
  }.freeze

  attr_reader :image_path, :phash, :ahash, :dhash, :histogram

  def initialize(image_path)
    @image_path = image_path
    raise "文件不存在: #{image_path}" unless File.exist?(image_path)

    # 不保存 @image 实例变量，避免长期持有图片引用
    # 在每个方法中按需加载和释放

    # 计算所有哈希值
    @phash = calculate_phash
    @ahash = calculate_ahash
    @dhash = calculate_dhash
    @histogram = calculate_histogram
  end

  # ===== pHash (感知哈希) =====
  def calculate_phash
    grayscale = resize_and_grayscale
    dct = dct_transform(grayscale)

    low_freq = []
    HASH_SIZE.times do |y|
      HASH_SIZE.times do |x|
        low_freq << dct[y][x]
      end
    end
    avg = low_freq.sum.to_f / low_freq.size

    hash_bits = low_freq.map { |val| val > avg ? 1 : 0 }
    hash_bits.join.to_i(2)
  end

  # ===== aHash (平均哈希) =====
  def calculate_ahash
    grayscale = resize_and_grayscale

    # 计算平均灰度值
    sum = 0
    grayscale.each { |row| sum += row.sum }
    avg = sum.to_f / (IMG_SIZE * IMG_SIZE)

    # 生成哈希
    hash_bits = []
    grayscale.each do |row|
      row.each do |pixel|
        hash_bits << (pixel > avg ? 1 : 0)
      end
    end

    hash_bits.join.to_i(2)
  end

  # ===== dHash (差分哈希) =====
  def calculate_dhash
    # 使用9x8的图片（需要比较相邻像素）
    img = nil
    grayscale = nil
    hash_bits = []

    begin
      img = Magick::Image.read(@image_path).first
      img = img.resize(9, 8)
      img = img.quantize(256, Magick::GRAYColorspace)

      grayscale = Array.new(8) { Array.new(9) }
      8.times do |y|
        9.times do |x|
          pixel = img.pixel_color(x, y)
          grayscale[y][x] = (pixel.red * 255.0 / Magick::QuantumRange).round
        end
      end

      # 比较每行相邻像素
      8.times do |y|
        8.times do |x|
          hash_bits << (grayscale[y][x] > grayscale[y][x + 1] ? 1 : 0)
        end
      end

      hash_bits.join.to_i(2)
    ensure
      # 及时释放图片对象和数组的内存引用
      if img
        img.destroy!
        img = nil
      end
      grayscale = nil
      hash_bits = nil
    end
  end

  # ===== 直方图计算 =====
  def calculate_histogram
    img = nil
    histogram = nil

    begin
      img = Magick::Image.read(@image_path).first

      # 转换为灰度图
      img = img.quantize(256, Magick::GRAYColorspace)

      # 统计灰度直方图
      histogram = Array.new(HISTOGRAM_BINS, 0)
      total_pixels = img.rows * img.columns

      img.rows.times do |y|
        img.columns.times do |x|
          pixel = img.pixel_color(x, y)
          gray_value = (pixel.red * 255.0 / Magick::QuantumRange).round
          histogram[gray_value] += 1
        end
      end

      # 归一化
      normalized = histogram.map { |count| count.to_f / total_pixels }
      normalized
    ensure
      # 及时释放图片对象和数组的内存引用
      if img
        img.destroy!
        img = nil
      end
      histogram = nil
    end
  end

  # ===== 辅助方法 =====
  def resize_and_grayscale
    img = nil
    grayscale = nil

    begin
      img = Magick::Image.read(@image_path).first
      img = img.resize(IMG_SIZE, IMG_SIZE)
      img = img.quantize(256, Magick::GRAYColorspace)

      grayscale = Array.new(IMG_SIZE) { Array.new(IMG_SIZE) }
      IMG_SIZE.times do |y|
        IMG_SIZE.times do |x|
          pixel = img.pixel_color(x, y)
          gray_value = (pixel.red * 255.0 / Magick::QuantumRange).round
          grayscale[y][x] = gray_value
        end
      end

      grayscale
    ensure
      # 及时释放图片对象的内存引用
      if img
        img.destroy!
        img = nil
      end
    end
  end

  def dct_transform(pixels)
    n = pixels.size
    dct = Array.new(n) { Array.new(n, 0.0) }

    n.times do |u|
      n.times do |v|
        sum = 0.0
        n.times do |x|
          n.times do |y|
            sum += pixels[y][x] *
                   Math.cos((2 * x + 1) * u * Math::PI / (2.0 * n)) *
                   Math.cos((2 * y + 1) * v * Math::PI / (2.0 * n))
          end
        end

        cu = u.zero? ? 1.0 / Math.sqrt(2) : 1.0
        cv = v.zero? ? 1.0 / Math.sqrt(2) : 1.0
        dct[u][v] = 0.25 * cu * cv * sum
      end
    end

    dct
  end

  # ===== 相似度比较方法 =====

  # 计算汉明距离
  def self.hamming_distance(hash1, hash2)
    (hash1 ^ hash2).to_s(2).count('1')
  end

  # 哈希相似度（0-100）
  def self.hash_similarity(hash1, hash2, bits = 64)
    hamming_dist = hamming_distance(hash1, hash2)
    (1 - hamming_dist.to_f / bits) * 100
  end

  # 直方图相似度（使用巴氏系数）
  def self.histogram_similarity(hist1, hist2)
    return 0.0 if hist1.size != hist2.size

    # 巴氏系数
    bc = 0.0
    hist1.size.times do |i|
      bc += Math.sqrt(hist1[i] * hist2[i])
    end

    bc * 100  # 转换为百分比
  end

  # 综合相似度（加权平均）
  def self.compare(image1_path, image2_path)
    img1 = nil
    img2 = nil
    result = nil

    begin
      img1 = new(image1_path)
      img2 = new(image2_path)

      # 计算各个算法的相似度
      phash_sim = hash_similarity(img1.phash, img2.phash, 64)
      ahash_sim = hash_similarity(img1.ahash, img2.ahash, 1024)  # 32x32 bits
      dhash_sim = hash_similarity(img1.dhash, img2.dhash, 64)    # 8x8 bits
      histogram_sim = histogram_similarity(img1.histogram, img2.histogram)

      # 加权平均
      weighted_similarity =
        phash_sim * WEIGHTS[:phash] +
        ahash_sim * WEIGHTS[:ahash] +
        dhash_sim * WEIGHTS[:dhash] +
        histogram_sim * WEIGHTS[:histogram]

      # 临时读取 img2 的尺寸信息
      img2_temp = nil
      begin
        img2_temp = Magick::Image.read(image2_path).first
        img2_dims = { width: img2_temp.columns, height: img2_temp.rows }
      ensure
        if img2_temp
          img2_temp.destroy!
          img2_temp = nil
        end
      end

      result = {
        image1: image1_path,
        image2: image2_path,
        similarity: weighted_similarity,
        details: {
          phash: phash_sim.round(2),
          ahash: ahash_sim.round(2),
          dhash: dhash_sim.round(2),
          histogram: histogram_sim.round(2)
        },
        weights: WEIGHTS,
        img2_dims: img2_dims
      }
      result
    ensure
      # 及时释放 ImageComparator 对象
      img1 = nil
      img2 = nil
    end
  end

  # 快速比较（只用于已有实例）
  def self.quick_compare(img1, img2)
    phash_sim = hash_similarity(img1.phash, img2.phash, 64)
    ahash_sim = hash_similarity(img1.ahash, img2.ahash, 1024)
    dhash_sim = hash_similarity(img1.dhash, img2.dhash, 64)
    histogram_sim = histogram_similarity(img1.histogram, img2.histogram)

    phash_sim * WEIGHTS[:phash] +
    ahash_sim * WEIGHTS[:ahash] +
    dhash_sim * WEIGHTS[:dhash] +
    histogram_sim * WEIGHTS[:histogram]
  end
end

