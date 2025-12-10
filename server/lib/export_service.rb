require 'csv'

class ExportService
  def initialize(project, use_placeholder: true, only_confirmed: false, output_path: nil)
    @project = project
    @use_placeholder = use_placeholder
    @only_confirmed = only_confirmed
    @output_path = output_path
    @no_match_files = []
    @error_logs = []
    @placeholder_path = File.join(File.dirname(__FILE__), '..', 'assets', 'placeholder_no_match.png')
    @progress = { total: 0, processed: 0, current: "" }
    @resolved_output_path = nil  # 存储解析后的真实导出路径
  end

  def process
    # 导出用户已确认的图片匹配结果
    # 按目标列（语言）组织导出
    output_root = @output_path && !@output_path.empty? ? @output_path : @project.output_path

    # 扩展路径：处理 ~, 相对路径等
    # 如果是相对路径,基于项目源路径所在目录展开，确保用户输入的路径生效
    if output_root.start_with?('~')
      # 处理 ~ 开头的路径（用户主目录）
      output_root = File.expand_path(output_root)
    elsif !output_root.start_with?('/')
      # 相对路径：基于项目源路径的父目录展开
      base_dir = File.dirname(@project.source_path)
      output_root = File.expand_path(output_root, base_dir)
    else
      # 绝对路径：直接使用
      output_root = File.expand_path(output_root)
    end

    # 保存解析后的路径供后续使用
    @resolved_output_path = output_root

    # 如果目录不存在，先创建
    FileUtils.mkdir_p(output_root)

    # 根据 only_confirmed 参数决定导出哪些源文件
    sources = if @only_confirmed
      SourceFile
        .joins(:source_confirmation)
        .where(project_id: @project.id, source_confirmations: { confirmed: true })
    else
      SourceFile.where(project_id: @project.id)
    end

    # 计算总任务数
    @progress[:total] = sources.count * @project.project_targets.count
    save_progress

    # 按目标列组织导出
    @project.project_targets.each do |target|
      target_dir = File.join(output_root, target.name)
      FileUtils.mkdir_p(target_dir)
      puts "Processing target: #{target.name}"

      sources.each do |source|
        @progress[:current] = "#{target.name}/#{source.relative_path}"
        save_progress

        # 获取该源文件在当前目标的选择
        target_selection = TargetSelection.find_by(
          source_file_id: source.id,
          project_target_id: target.id
        )

        if target_selection && target_selection.no_match
          # 记录到 no_match 报告
          @no_match_files << "#{target.name}: #{source.relative_path}"
          # 生成占位图片（如果启用）
          if @use_placeholder
            export_placeholder_image(source, target_dir)
          end
        elsif target_selection && target_selection.selected_candidate_id
          # 导出选中的候选项
          export_candidate(source, target_selection.selected_candidate_id, target_dir, target.name)
        else
          # 未选择 - 按"无匹配"处理
          @no_match_files << "#{target.name}: #{source.relative_path} (未选择)"
          if @use_placeholder
            export_placeholder_image(source, target_dir)
          end
        end

        @progress[:processed] += 1
        save_progress
      end
    end

    # 生成报告
    generate_report(output_root)
    generate_error_log(output_root) if @error_logs.any?

    puts "Export completed to: #{output_root}"
    @progress[:current] = "完成"
    save_progress
  end

  def get_progress
    @progress
  end

  private

  def save_progress
    # 将进度保存到数据库或缓存中，供前端查询
    # 这里使用简单的文件缓存
    # 使用实际的导出路径，而不是项目默认路径
    progress_dir = @resolved_output_path || @project.output_path
    progress_file = File.join(progress_dir, '.export_progress.json')
    FileUtils.mkdir_p(File.dirname(progress_file))
    File.write(progress_file, @progress.to_json)
  rescue => e
    puts "Error saving progress: #{e.message}"
  end

  def generate_report(output_root)
    return if @no_match_files.empty?

    report_path = File.join(output_root, 'no_match_report.csv')
    CSV.open(report_path, 'w') do |csv|
      csv << ['Target', 'Source File', 'Status']
      @no_match_files.each do |entry|
        csv << [entry, 'No Match or Not Selected']
      end
    end

    puts "Generated no-match report: #{report_path}"
  end

  def generate_error_log(output_root)
    return if @error_logs.empty?

    error_log_path = File.join(output_root, 'export_errors.log')
    File.open(error_log_path, 'w') do |f|
      f.puts "Export Error Log - Generated at #{Time.now}"
      f.puts "=" * 60
      @error_logs.each do |error|
        f.puts error
      end
    end

    puts "Generated error log: #{error_log_path}"
  end

  def export_candidate(source_file, candidate_id, target_dir, target_name)
    cand = ComparisonCandidate.find_by(id: candidate_id)

    unless cand
      error_msg = "[#{Time.now}] Candidate not found: ID=#{candidate_id} for #{source_file.relative_path} (Target: #{target_name})"
      @error_logs << error_msg
      puts error_msg
      return
    end

    unless File.exist?(cand.file_path)
      error_msg = "[#{Time.now}] File not found: #{cand.file_path} for #{source_file.relative_path} (Target: #{target_name})"
      @error_logs << error_msg
      puts error_msg
      return
    end

    # 输出目录结构: [Target Dir] / [Source Relative Path Dir]
    relative_dir = File.dirname(source_file.relative_path)
    # 规范化路径：去除 '.', '..', 多余的斜杠等
    relative_dir = Pathname.new(relative_dir).cleanpath.to_s

    # 如果文件在根目录，dirname 返回 '.'，需要排除
    dest_dir = if relative_dir == '.' || relative_dir.empty?
      target_dir
    else
      # 安全检查：防止路径遍历攻击
      if relative_dir.include?('..') || relative_dir.start_with?('/')
        puts "[WARNING] Invalid relative path detected: #{relative_dir}, using target_dir only"
        target_dir
      else
        File.join(target_dir, relative_dir)
      end
    end
    FileUtils.mkdir_p(dest_dir)

    # 文件名: 保持和源文件完全一致（包括扩展名）
    dest_filename = File.basename(source_file.relative_path)
    dest_path = File.join(dest_dir, dest_filename)

    # 复制文件
    begin
      FileUtils.cp(cand.file_path, dest_path)
      puts "Exported (#{target_name}): #{source_file.relative_path} -> #{dest_path}"
    rescue => e
      error_msg = "[#{Time.now}] Error exporting #{cand.file_path} to #{dest_path}: #{e.message}"
      @error_logs << error_msg
      puts error_msg
    end
  end

  def export_placeholder_image(source_file, target_dir)
    # 复制占位图片到目标位置，文件名保持和源文件一致
    unless File.exist?(@placeholder_path)
      error_msg = "[#{Time.now}] Placeholder image not found: #{@placeholder_path}"
      @error_logs << error_msg
      puts error_msg
      return
    end

    relative_dir = File.dirname(source_file.relative_path)
    # 规范化路径：去除 '.', '..', 多余的斜杠等
    relative_dir = Pathname.new(relative_dir).cleanpath.to_s

    # 如果文件在根目录，dirname 返回 '.'，需要排除
    dest_dir = if relative_dir == '.' || relative_dir.empty?
      target_dir
    else
      # 安全检查：防止路径遍历攻击
      if relative_dir.include?('..') || relative_dir.start_with?('/')
        puts "[WARNING] Invalid relative path detected: #{relative_dir}, using target_dir only"
        target_dir
      else
        File.join(target_dir, relative_dir)
      end
    end
    FileUtils.mkdir_p(dest_dir)

    # 保持源文件名
    dest_filename = File.basename(source_file.relative_path)
    dest_path = File.join(dest_dir, dest_filename)

    begin
      FileUtils.cp(@placeholder_path, dest_path)
      puts "Exported placeholder: #{dest_path}"
    rescue => e
      error_msg = "[#{Time.now}] Error exporting placeholder to #{dest_path}: #{e.message}"
      @error_logs << error_msg
      puts error_msg
    end
  end
end
