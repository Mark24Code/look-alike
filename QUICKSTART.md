# Look Alike - 快速启动指南

## 🚀 最简单的使用方式

### 1. 构建前端（只需一次）
```bash
cd client
npm install
npm run build
cd ..
```

### 2. 编译服务器（只需一次）
```bash
make build
```

### 3. 启动服务
```bash
./look-alike-server
```

就这么简单！打开浏览器访问：**http://localhost:4568**

## 📦 一键完成所有操作

使用 Makefile 自动完成所有步骤：

```bash
# 安装依赖 + 构建前端 + 编译服务器 + 启动
make start-prod
```

## 🔥 特性

- ✅ **单一可执行文件**：无需安装 Ruby 或其他依赖
- ✅ **集成前端**：Go 服务器直接提供前端页面
- ✅ **快速启动**：从启动到可用只需 0.1 秒
- ✅ **零配置**：开箱即用

## 📋 Makefile 命令速查

```bash
make help          # 显示所有命令
make build         # 编译服务器
make build-client  # 构建前端
make start-prod    # 生产模式（推荐）
make dev           # 开发模式（不构建，直接运行）
make clean         # 清理构建文件
```

## 🌐 访问地址

启动后可以访问：

- **前端界面**：http://localhost:4568
- **API接口**：http://localhost:4568/api/health
- **健康检查**：http://localhost:4568/api/health

## 💡 开发模式（可选）

如果你需要修改代码并实时查看效果：

```bash
# 终端1：运行 Go 服务器
make dev

# 终端2：运行前端开发服务器（可选）
cd client && npm run dev
# 前端访问 http://localhost:5174
```

## 📂 项目结构

```
look-alike/
├── look-alike-server    # ✨ 编译后的可执行文件（33MB）
├── client/
│   └── dist/           # 前端构建产物
├── db/
│   └── look_alike.sqlite3  # 数据库文件
└── go-server/          # Go 源代码
```

## ⚙️ 配置

### 环境变量

- `PORT`：服务器端口（默认：4568）
- `GIN_MODE`：Gin模式（建议生产环境设置为 `release`）

示例：
```bash
export GIN_MODE=release
export PORT=8080
./look-alike-server
```

## 🐛 故障排查

### 问题：端口被占用

```bash
# 查找占用4568端口的进程
lsof -ti:4568

# 杀死进程
kill $(lsof -ti:4568)
```

### 问题：前端显示 404

确保已构建前端：
```bash
cd client && npm run build
```

### 问题：数据库文件不存在

创建 db 目录：
```bash
mkdir -p db
```

数据库文件会在首次启动时自动创建。

## 🎯 下一步

1. 访问 http://localhost:4568
2. 创建新项目
3. 上传图片进行相似度比对
4. 查看匹配结果

## 📖 详细文档

- [完整 README](README.md)
- [Go Server 文档](go-server/README.md)

## ⚡ 性能特点

| 指标 | 数值 |
|------|------|
| 可执行文件大小 | 33 MB |
| 启动时间 | ~0.1 秒 |
| 内存占用 | ~50 MB (空闲) |
| 并发处理 | 4 个 goroutines |

## 🎉 享受使用！
