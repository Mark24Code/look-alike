require 'fileutils'

# 项目根目录
ROOT_DIR = __dir__
SERVER_DIR = File.join(ROOT_DIR, 'server')
CLIENT_DIR = File.join(ROOT_DIR, 'client')
DB_FILE = File.join(SERVER_DIR, 'db', 'look_alike.sqlite3')

# 颜色输出
def colorize(text, color_code)
  "\e[#{color_code}m#{text}\e[0m"
end

def info(msg)
  puts colorize("✓ #{msg}", 32) # 绿色
end

def warn(msg)
  puts colorize("⚠ #{msg}", 33) # 黄色
end

def error(msg)
  puts colorize("✗ #{msg}", 31) # 红色
end

def section(msg)
  puts "\n" + colorize("▶ #{msg}", 36) # 青色
end

# 默认任务
task default: :help

desc "显示所有可用的任务"
task :help do
  puts colorize("\n=== Look-Alike 项目管理工具 ===\n", 35)
  puts "可用任务:"
  puts "  rake start:dev      - 启动开发模式 (前端+后端分别运行)"
  puts "  rake start:prod     - 启动生产模式 (后端提供前端静态文件)"
  puts "  rake start:server   - 启动后端服务 (端口 4568)"
  puts "  rake start:client   - 启动前端开发服务器 (端口 5174)"
  puts ""
  puts "  rake build:client   - 构建前端生产版本"
  puts ""
  puts "  rake db:setup       - 初始化数据库 (创建+迁移)"
  puts "  rake db:reset       - 重置数据库 (删除+创建+迁移)"
  puts "  rake db:migrate     - 运行数据库迁移"
  puts "  rake db:rollback    - 回滚最近一次迁移"
  puts "  rake db:seed        - 填充测试数据"
  puts "  rake db:status      - 查看数据库状态"
  puts ""
  puts "  rake install        - 安装所有依赖 (前端+后端)"
  puts "  rake install:server - 安装后端依赖"
  puts "  rake install:client - 安装前端依赖"
  puts ""
  puts "  rake clean          - 清理临时文件"
  puts "  rake test           - 运行测试"
  puts ""
end

# ============= 启动任务 =============

namespace :start do
  desc "启动开发模式 (前端+后端分别运行)"
  task :dev do
    section "启动开发模式"

    # 检查依赖
    unless system("which bundle > /dev/null 2>&1")
      error "请先安装 Bundler: gem install bundler"
      exit 1
    end

    unless system("which npm > /dev/null 2>&1")
      error "请先安装 Node.js 和 npm"
      exit 1
    end

    # 检查数据库
    unless File.exist?(DB_FILE)
      warn "数据库不存在,正在初始化..."
      Rake::Task['db:setup'].invoke
    end

    info "启动后端服务 (端口 4568)..."
    server_pid = spawn("cd #{SERVER_DIR} && bundle exec ruby app.rb")

    sleep 2

    info "启动前端服务 (端口 5174)..."
    client_pid = spawn("cd #{CLIENT_DIR} && npm run dev")

    puts "\n" + colorize("=" * 60, 36)
    info "开发模式已启动!"
    puts "  后端 API: http://localhost:4568/api/health"
    puts "  前端开发: http://localhost:5174"
    puts colorize("=" * 60, 36)
    puts "\n按 Ctrl+C 停止所有服务\n\n"

    # 等待并处理退出
    trap("INT") do
      puts "\n"
      section "正在停止服务..."
      Process.kill("TERM", server_pid) rescue nil
      Process.kill("TERM", client_pid) rescue nil
      info "所有服务已停止"
      exit
    end

    Process.wait
  end

  desc "启动生产模式 (后端提供前端静态文件)"
  task :prod do
    section "启动生产模式"

    # 检查前端构建产物
    dist_dir = File.join(CLIENT_DIR, 'dist')
    unless File.exist?(File.join(dist_dir, 'index.html'))
      warn "前端构建产物不存在，正在构建..."
      Rake::Task['build:client'].invoke
    end

    # 检查数据库
    unless File.exist?(DB_FILE)
      warn "数据库不存在,正在初始化..."
      Rake::Task['db:setup'].invoke
    end

    info "启动后端服务 (生产模式, 端口 4568)..."

    puts "\n" + colorize("=" * 60, 36)
    info "生产模式已启动!"
    puts "  访问地址: http://localhost:4568"
    puts "  健康检查: http://localhost:4568/api/health"
    puts colorize("=" * 60, 36)
    puts "\n按 Ctrl+C 停止服务\n\n"

    Dir.chdir(SERVER_DIR) do
      exec "bundle exec ruby app.rb"
    end
  end

  desc "启动后端服务"
  task :server do
    section "启动后端服务"

    unless File.exist?(DB_FILE)
      warn "数据库不存在,正在初始化..."
      Rake::Task['db:setup'].invoke
    end

    Dir.chdir(SERVER_DIR) do
      info "后端服务正在启动 (端口 4568)..."
      exec "bundle exec ruby app.rb"
    end
  end

  desc "启动前端开发服务器"
  task :client do
    section "启动前端开发服务器"
    Dir.chdir(CLIENT_DIR) do
      info "前端服务正在启动 (端口 5174)..."
      exec "npm run dev"
    end
  end
end

# ============= 数据库任务 =============

namespace :db do
  desc "初始化数据库 (创建并运行迁移)"
  task :setup do
    section "初始化数据库"
    Dir.chdir(SERVER_DIR) do
      info "创建数据库..."
      sh "bundle exec rake db:create"
      info "运行迁移..."
      sh "bundle exec rake db:migrate"
      info "数据库初始化完成"
    end
  end

  desc "重置数据库 (删除、创建、迁移)"
  task :reset do
    section "重置数据库"
    Dir.chdir(SERVER_DIR) do
      if File.exist?(DB_FILE)
        warn "删除现有数据库..."
        sh "bundle exec rake db:drop"
      end
      info "创建数据库..."
      sh "bundle exec rake db:create"
      info "运行迁移..."
      sh "bundle exec rake db:migrate"
      info "数据库重置完成"
    end
  end

  desc "运行数据库迁移"
  task :migrate do
    section "运行数据库迁移"
    Dir.chdir(SERVER_DIR) do
      sh "bundle exec rake db:migrate"
      info "迁移完成"
    end
  end

  desc "回滚最近一次迁移"
  task :rollback do
    section "回滚数据库迁移"
    Dir.chdir(SERVER_DIR) do
      sh "bundle exec rake db:rollback"
      info "回滚完成"
    end
  end

  desc "查看数据库迁移状态"
  task :status do
    section "数据库状态"
    Dir.chdir(SERVER_DIR) do
      sh "bundle exec rake db:migrate:status"
    end
  end

  desc "填充测试数据"
  task :seed do
    section "填充测试数据"
    Dir.chdir(SERVER_DIR) do
      require './app'

      # 创建测试项目
      project = Project.create!(
        name: "测试项目",
        source_path: "/path/to/source",
        status: "pending"
      )

      # 创建测试目标
      target = ProjectTarget.create!(
        project: project,
        name: "目标库1",
        path: "/path/to/target"
      )

      info "已创建测试项目: #{project.name} (ID: #{project.id})"
      info "已创建测试目标: #{target.name} (ID: #{target.id})"
    end
  end
end

# ============= 安装任务 =============

desc "安装所有依赖"
task :install => ['install:server', 'install:client']

namespace :install do
  desc "安装后端依赖"
  task :server do
    section "安装后端依赖"
    Dir.chdir(SERVER_DIR) do
      sh "bundle install"
      info "后端依赖安装完成"
    end
  end

  desc "安装前端依赖"
  task :client do
    section "安装前端依赖"
    Dir.chdir(CLIENT_DIR) do
      sh "npm install"
      info "前端依赖安装完成"
    end
  end
end

# ============= 清理任务 =============

desc "清理临时文件和日志"
task :clean do
  section "清理临时文件"

  # 清理后端临时文件
  [
    File.join(SERVER_DIR, 'db', '*.sqlite3-shm'),
    File.join(SERVER_DIR, 'db', '*.sqlite3-wal'),
    File.join(SERVER_DIR, 'log', '*.log'),
    File.join(SERVER_DIR, 'tmp', '**', '*')
  ].each do |pattern|
    Dir.glob(pattern).each do |file|
      FileUtils.rm_f(file)
      info "删除: #{file}"
    end
  end

  info "清理完成"
end

# ============= 测试任务 =============

desc "运行测试"
task :test do
  section "运行测试"
  warn "测试任务尚未配置"
  # TODO: 添加测试任务
end

# ============= 构建任务 =============

namespace :build do
  desc "构建前端生产版本"
  task :client do
    section "构建前端"
    Dir.chdir(CLIENT_DIR) do
      sh "npm run build"
      info "前端构建完成,输出目录: #{File.join(CLIENT_DIR, 'dist')}"
    end
  end
end
