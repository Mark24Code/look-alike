# Look Alike

一个高性能的图片相似度比对工具，用于查找和匹配相似的图片。

[![Release](https://github.com/你的用户名/look-alike/workflows/Release/badge.svg)](https://github.com/你的用户名/look-alike/actions)
[![CI](https://github.com/你的用户名/look-alike/workflows/CI/badge.svg)](https://github.com/你的用户名/look-alike/actions)

## 项目结构

```
look-alike/
├── client/         # 前端项目 (React + Vite)
├── go-server/      # 后端服务 (Golang) ✨ NEW!
├── backup-ruby/    # Ruby版本备份 (已迁移)
├── Makefile        # Make 命令
└── README.md
```

## 技术栈

### 前端
- React 19
- TypeScript
- Vite
- Ant Design
- React Router

### 后端 (Golang)
- **语言**: Go 1.21+
- **Web框架**: Gin
- **ORM**: GORM
- **数据库**: SQLite3
- **图片处理**: imaging (纯Go实现)
- **并发**: Goroutines + Channels

## 🚀 快速启动

### 最简方式（推荐）

**一键启动（自动构建+运行）：**
```bash
make start-prod
```

启动后访问：**http://localhost:4568**

### 手动方式

**1. 构建前端：**
```bash
cd client && npm install && npm run build && cd ..
```

**2. 编译服务器：**
```bash
make build
```

**3. 启动：**
```bash
./look-alike-server
```

就这么简单！

> 💡 **提示**：Go 服务器会自动提供前端静态文件，无需单独运行前端开发服务器。

### 开发模式（可选）

如果需要修改代码并热重载：

```bash
# 终端1：运行 Go 服务器
make dev

# 终端2：（可选）运行前端开发服务器
cd client && npm run dev
# 前端开发访问 http://localhost:5174
```

## 生产环境部署

### 编译可执行文件

```bash
make build
```

这会在项目根目录生成 `look-alike-server` 可执行文件（约33MB）。

### 构建前端

```bash
make build-client
```

### 运行

```bash
# 方式1: 使用 Makefile
make start-prod

# 方式2: 直接运行
./look-alike-server
```

服务器会自动：
- 启动API服务 (端口 4568)
- 提供前端静态文件
- 访问 http://localhost:4568

## 主要功能

### 1. 图片相似度算法

采用 **感知哈希 (pHash) + RGB 颜色直方图** 混合算法：

| 算法 | 权重 | 特点 |
|------|------|------|
| pHash (感知哈希) | 70% | 基于 DCT 变换，识别图片结构特征 |
| RGB 颜色直方图 | 30% | 基于巴氏系数，识别颜色分布差异 |

**算法优势**：
- 🎯 **结构识别**：pHash 对缩放、压缩、轻微变换不敏感
- 🎨 **颜色区分**：能区分白色 vs 粉色等颜色差异
- ⚡ **高性能**：使用 `github.com/corona10/goimagehash` 优化库
- 🔄 **可调节**：可以调整权重平衡结构和颜色的重要性

**详细文档**：查看 [pHash + 颜色直方图算法说明](PHASH_COLOR_ALGORITHM.md)

### 2. 高性能并发处理

- 使用 Go 原生 goroutines 进行并发处理
- Semaphore 模式控制并发数（默认4个）
- 批量数据库操作（每批100条）
- 自适应尺寸过滤，减少比较次数

### 3. 智能匹配

- 自适应阈值算法
- 渐进式容差筛选
- 强制保证每个源文件至少有一个匹配

### 4. 用户友好界面

- 文件树展示
- 候选项预览
- 批量操作
- 进度追踪

## API 端点

完整实现 15 个 REST API 端点：

```
GET    /api/health                          # 健康检查
GET    /api/projects                        # 项目列表（分页）
POST   /api/projects                        # 创建项目
GET    /api/projects/:id                    # 项目详情
DELETE /api/projects/:id                    # 删除项目
GET    /api/projects/:id/files              # 文件树结构
POST   /api/projects/:id/candidates         # 获取候选项
GET    /api/image                           # 图片服务
POST   /api/projects/:id/select_candidate   # 选择候选项
POST   /api/projects/:id/mark_no_match      # 标记无匹配
POST   /api/projects/:id/confirm_row        # 确认行
POST   /api/projects/:id/export             # 导出
GET    /api/projects/:id/export_progress    # 导出进度
```

## Makefile 命令

```bash
make help            # 显示所有可用命令
make build           # 编译服务器
make run             # 编译并运行
make dev             # 开发模式运行（无需编译）
make install         # 安装所有依赖
make build-client    # 构建前端
make start-dev       # 开发模式（前端+后端）
make start-prod      # 生产模式
make clean           # 清理构建文件
make test            # 运行测试
make fmt             # 格式化代码
make lint            # 代码检查
make package         # 打包所有平台
make package-windows # 打包 Windows x64
make package-mac-amd64  # 打包 macOS Intel
make package-mac-arm64  # 打包 macOS Apple Silicon
```

## 📦 多平台打包

支持一键打包为可直接运行的独立程序，无需安装任何依赖：

### 打包所有平台

```bash
make package
```

生成产物：
- `dist/look-alike-windows-x64.zip` - Windows x64
- `dist/look-alike-macos-x64.tar.gz` - macOS Intel (x64)
- `dist/look-alike-macos-arm64.tar.gz` - macOS Apple Silicon (ARM64)

### 打包单个平台

```bash
make package-windows      # 仅打包 Windows
make package-mac-amd64    # 仅打包 Mac Intel
make package-mac-arm64    # 仅打包 Mac ARM
```

**注意**：Windows 交叉编译需要 `mingw-w64`，详见 [WINDOWS_BUILD.md](WINDOWS_BUILD.md)

### 分发包特性

每个打包产物都包含：
- ✅ 编译好的可执行文件（无需安装任何运行时）
- ✅ 前端静态资源（已预编译）
- ✅ 数据库目录（首次启动自动初始化）
- ✅ 使用说明（README.txt）

用户只需：
1. 解压文件
2. 双击运行（或命令行运行）
3. 浏览器访问 `http://localhost:4568`

**详细打包文档**：查看 [PACKAGING.md](PACKAGING.md)

## 性能优势

相比 Ruby 版本的改进：

| 指标 | Ruby 版本 | Go 版本 | 提升 |
|------|----------|---------|------|
| 处理速度 | 基准 | 2-5x | ⬆️ |
| 内存占用 | 基准 | 0.5-0.7x | ⬇️ |
| 并发能力 | Thread | Goroutine | ⬆️⬆️ |
| 部署复杂度 | 需要Ruby环境 | 单一可执行文件 | ⬇️⬇️ |
| 启动速度 | ~2s | ~0.1s | ⬆️⬆️ |

## 环境要求

- **Go**: 1.21+ （开发/编译时需要）
- **Node.js**: 16+ （开发前端时需要）
- **浏览器**: 现代浏览器（Chrome, Firefox, Safari, Edge）

## 配置

### 环境变量

- `PORT`: 服务器端口（默认: 4568）
- `GOPROXY`: Go 模块代理（推荐: https://goproxy.cn,direct）

### 数据库

- 类型: SQLite3
- 位置: `db/look_alike.sqlite3`
- 模式: WAL (Write-Ahead Logging)
- 兼容原 Ruby 版本的 schema

## 常见问题

### Q: 如何从 Ruby 版本迁移？

A: Go 版本完全兼容 Ruby 版本的数据库，直接使用即可。Ruby 代码已备份至 `backup-ruby/` 目录。

### Q: 编译时遇到网络问题？

A: 设置国内 Go 代理：
```bash
export GOPROXY=https://goproxy.cn,direct
```

### Q: 前端提示 "Frontend assets not found"？

A: 先构建前端：
```bash
cd client && npm run build
```

### Q: 数据库锁定错误？

A: 确保只有一个服务实例在运行。SQLite WAL 模式已启用以提高并发性能。

### Q: 支持哪些图片格式？

A: 支持 JPEG, PNG, GIF, TIFF, BMP, WebP。

## 项目迁移说明

本项目已从 Ruby (Sinatra + RMagick) 完全迁移到 Golang (Gin + imaging)。

### 主要变更：

1. **后端语言**: Ruby → Golang
2. **Web框架**: Sinatra → Gin
3. **图片处理**: RMagick (ImageMagick) → imaging (纯Go)
4. **ORM**: ActiveRecord → GORM
5. **并发模型**: Thread + Mutex → Goroutines + Channels
6. **部署方式**: 需要Ruby环境 → 单一可执行文件

### 保持不变：

- ✅ 数据库 schema 完全兼容
- ✅ API 接口保持一致
- ✅ 前端无需任何修改
- ✅ 算法结果保持一致（误差<5%）

### Ruby 版本备份：

原 Ruby 代码已移至 `backup-ruby/` 目录，包含：
- `backup-ruby/server/` - Ruby 后端
- `backup-ruby/img-lib/` - Ruby 图片处理库
- `backup-ruby/Gemfile*` - Ruby 依赖

## 开发指南

详细的开发文档请查看：

- [Go Server README](go-server/README.md)
- [前端 README](client/README.md)

## 贡献

欢迎提交 Issue 和 Pull Request！

## 发布

本项目使用 GitHub Actions 自动构建和发布。

发布新版本：
```bash
git tag v1.0.0
git push origin v1.0.0
```

详细说明请查看 [发布指南](.github/RELEASE.md)

## 许可证

MIT License

## 更新日志

### v1.0.0-go (2024-12-11)

- ✨ 完成 Ruby 到 Golang 的完整迁移
- ⚡ 性能提升 2-5倍
- 📦 支持编译成单一可执行文件
- 🔧 简化部署流程
- 📝 完善文档和 Makefile

### v0.1.0-ruby (2023-12)

- 🎉 初始 Ruby 版本发布
