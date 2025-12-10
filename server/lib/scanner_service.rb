class ScannerService
  def initialize(project)
    @project = project
  end

  def scan
    # 1. Index Source Directory
    scan_source_directory

    # 2. Index Target Directories (if needed, or just prepare them)
    # Target files are usually read on demand during comparison, 
    # but we might want to know how many there are or valid paths.
    
    @project.update(status: 'scanned') # Intermediate status? Or just part of 'processing'
  end

  private

  def scan_source_directory
    source_path = @project.source_path

    # Recursively find images
    # Using Dir.glob with common image extensions
    images = Dir.glob(File.join(source_path, "**", "*.{jpg,jpeg,png,webp,bmp}"))

    images.each do |full_path|
      relative_path = Pathname.new(full_path).relative_path_from(source_path).to_s

      # Basic check only
      next unless File.file?(full_path)

      # Read dimensions/size?
      # MiniMagick/RMagick is slow for just reading dimensions of ALL files if there are many.
      # But useful for the UI.
      # Let's do lazy loading or read now. For MVP read now to populate DB.

      size = File.size(full_path)

      # Check if exists
      unless SourceFile.exists?(project: @project, relative_path: relative_path)
        img = nil
        begin
          img = Magick::Image.ping(full_path).first

          SourceFile.create(
            project: @project,
            relative_path: relative_path,
            full_path: full_path,
            width: img.columns,
            height: img.rows,
            size_bytes: size,
            status: 'pending'
          )
        ensure
          # 及时释放图片对象的内存引用
          if img
            img.destroy!
            img = nil
          end
        end
      end
    end
  end
end
