# Look Alike - Golang Server

Go 语言实现的图片相似度比对工具后端服务。

## 技术栈

- **语言**: Go 1.21+
- **Web框架**: Gin
- **ORM**: GORM
- **数据库**: SQLite3
- **图片处理**: imaging (纯Go实现)

## 项目结构

```
go-server/
├── cmd/
│   └── server/          # 主程序入口
│       └── main.go
├── internal/
│   ├── api/             # API路由和处理器
│   │   ├── router.go
│   │   └── handlers.go
│   ├── models/          # 数据模型
│   │   └── models.go
│   ├── services/        # 业务逻辑服务
│   │   ├── indexing_service.go
│   │   ├── comparison_service.go
│   │   ├── export_service.go
│   │   └── dimension_filter.go
│   ├── workers/         # 并发处理
│   │   ├── worker_pool.go
│   │   └── thread_manager.go
│   ├── image/           # 图片处理算法
│   │   └── comparator.go
│   └── database/        # 数据库连接
│       └── database.go
├── configs/             # 配置文件
├── go.mod
└── go.sum
```

## 核心功能

### 1. 图片相似度算法

实现了4种图片哈希算法的组合：

- **pHash (感知哈希)** - 权重 40%
  - 基于DCT变换
  - 对缩放和压缩不敏感

- **aHash (平均哈希)** - 权重 20%
  - 基于平均灰度值
  - 简单快速

- **dHash (差分哈希)** - 权重 20%
  - 基于相邻像素差异
  - 对水平变化敏感

- **直方图比较** - 权重 20%
  - 使用巴氏系数
  - 对颜色分布敏感

### 2. 并发处理

使用 Go 原生的并发模式：

- **Goroutines**: 轻量级并发任务
- **Channels**: 任务通信和同步
- **sync.WaitGroup**: 等待任务完成
- **context.Context**: 任务取消控制
- **Semaphore模式**: 控制并发数量

### 3. 数据模型

兼容原 Ruby 版本的数据库 schema：

- Project - 项目
- ProjectTarget - 目标目录
- SourceFile - 源文件
- TargetFile - 目标文件
- ComparisonCandidate - 候选匹配
- TargetSelection - 用户选择
- SourceConfirmation - 确认状态

### 4. API 端点

完整实现所有 15 个 API 端点：

```
GET    /api/health                          # 健康检查
GET    /api/projects                        # 项目列表
POST   /api/projects                        # 创建项目
GET    /api/projects/:id                    # 项目详情
DELETE /api/projects/:id                    # 删除项目
GET    /api/projects/:id/files              # 文件树
POST   /api/projects/:id/candidates         # 获取候选项
GET    /api/image                           # 图片服务
POST   /api/projects/:id/select_candidate   # 选择候选项
POST   /api/projects/:id/mark_no_match      # 标记无匹配
POST   /api/projects/:id/confirm_row        # 确认行
POST   /api/projects/:id/export             # 导出
GET    /api/projects/:id/export_progress    # 导出进度
```

## 开发指南

### 环境要求

- Go 1.21+
- ImageMagick (可选，已不需要)
- SQLite3

### 安装依赖

```bash
cd go-server
GOPROXY=https://goproxy.cn,direct go mod download
```

### 开发模式运行

```bash
cd go-server
go run ./cmd/server
```

或使用 Makefile：

```bash
make dev
```

### 编译

```bash
cd go-server
go build -o ../look-alike-server ./cmd/server
```

或使用 Makefile：

```bash
make build
```

### 运行测试

```bash
cd go-server
go test ./...
```

## 配置

### 环境变量

- `PORT`: 服务器端口（默认: 4568）
- `DB_PATH`: 数据库路径（默认: ../db/look_alike.sqlite3）

### 数据库

使用 SQLite3，配置：

- `PRAGMA journal_mode=WAL` - 写前日志模式
- `PRAGMA synchronous=NORMAL` - 同步模式

## 性能优化

### 并发处理

- 索引服务：4个并发 goroutines
- 比较服务：4个并发 goroutines
- 使用 semaphore 模式限制并发数

### 批量操作

- 批量插入候选项：每批100条
- 批量更新状态：每批100条
- 减少数据库往返次数

### 内存管理

- 及时释放图片对象
- 避免在 goroutine 中持有大对象引用

## 与 Ruby 版本的差异

### 优势

1. **性能**: Go 的并发性能更好，预期处理速度提升 2-5倍
2. **部署**: 单一可执行文件，无需 Ruby 环境
3. **跨平台**: 更容易跨平台编译
4. **类型安全**: 静态类型检查减少运行时错误
5. **资源占用**: 内存占用更低

### 实现差异

1. **并发模型**:
   - Ruby: Thread + Mutex
   - Go: Goroutines + Channels

2. **图片处理库**:
   - Ruby: RMagick (ImageMagick绑定)
   - Go: imaging (纯Go实现)

3. **ORM**:
   - Ruby: ActiveRecord
   - Go: GORM

## 故障排查

### 编译错误

如果遇到网络问题，设置国内代理：

```bash
export GOPROXY=https://goproxy.cn,direct
go mod download
```

### 数据库锁定

确保只有一个进程访问数据库，或使用WAL模式。

### 图片格式不支持

`imaging` 库支持的格式：JPEG, PNG, GIF, TIFF, BMP, WebP

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License
