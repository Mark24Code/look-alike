# 打包指南

## 概述

本项目支持一键打包为多平台可执行程序，包括：
- Windows x64
- macOS Intel (x64)
- macOS Apple Silicon (ARM64)

每个打包产物都是完全独立的，包含：
- 编译好的服务器可执行文件
- 前端静态资源（dist）
- 数据库目录（自动创建）
- 使用说明（README.txt）

## 快速开始

### 打包所有平台

```bash
make package
```

这将生成：
- `dist/look-alike-windows-x64.zip` (Windows x64)
- `dist/look-alike-macos-x64.tar.gz` (macOS Intel)
- `dist/look-alike-macos-arm64.tar.gz` (macOS ARM64)

### 打包单个平台

```bash
# 仅打包 Windows x64
make package-windows

# 仅打包 macOS Intel (x64)
make package-mac-amd64

# 仅打包 macOS Apple Silicon (ARM64)
make package-mac-arm64
```

## 打包要求

### 前置条件

1. **Go 环境** (1.21+)
2. **Node.js** (18+)
3. **Make**

### 依赖安装

首次打包前，确保安装所有依赖：

```bash
make install
```

这会安装：
- Go 模块依赖
- npm 前端依赖

## 打包过程

打包脚本会自动执行以下步骤：

1. **清理旧构建** - 删除 `dist/` 目录
2. **构建前端** - 使用 `vite build` 编译 React 应用
3. **构建后端** - 针对每个平台使用 Go 交叉编译
4. **组装包** - 将可执行文件、前端、数据库目录打包
5. **生成归档** - 创建 `.zip` (Windows) 或 `.tar.gz` (macOS)

## 分发包结构

解压后的目录结构：

```
look-alike-macos-arm64/
├── look-alike              # 可执行文件
├── client/                 # 前端静态资源
│   ├── index.html
│   ├── assets/
│   └── vite.svg
├── db/                     # 数据库目录（启动时自动创建数据库）
└── README.txt              # 使用说明
```

## 数据库自动初始化

程序启动时会自动：
1. 检查 `db/` 目录是否存在，不存在则创建
2. 检查 `db/look_alike.sqlite3` 是否存在，不存在则创建
3. 自动运行数据库迁移，创建所有必要的表

**用户无需手动创建数据库**，首次启动会自动完成所有初始化。

## 使用分发包

### Windows

1. 解压 `look-alike-windows-x64.zip`
2. 双击 `look-alike.exe`
3. 浏览器访问 `http://localhost:4568`

### macOS

1. 解压 `look-alike-macos-arm64.tar.gz`
2. 在终端运行：
   ```bash
   cd look-alike-macos-arm64
   ./look-alike
   ```
3. 浏览器访问 `http://localhost:4568`

**注意**：首次运行可能需要在"系统偏好设置 > 安全性与隐私"中允许运行。

## 配置选项

### 更改端口

设置环境变量 `PORT`：

```bash
# macOS/Linux
PORT=8080 ./look-alike

# Windows
set PORT=8080
look-alike.exe
```

### 数据位置

- 数据库文件：`db/look_alike.sqlite3`
- 数据库自动备份（WAL）：`db/look_alike.sqlite3-wal`
- 所有项目数据都存储在数据库中

### 重置数据

删除数据库文件即可重置：

```bash
rm db/look_alike.sqlite3*
```

下次启动会自动创建新的空数据库。

## 故障排查

### 打包失败

1. **检查 Go 版本**：
   ```bash
   go version  # 需要 1.21+
   ```

2. **检查 Node.js 版本**：
   ```bash
   node --version  # 需要 18+
   ```

3. **清理并重试**：
   ```bash
   make clean
   make install
   make package
   ```

### 跨平台编译问题

如果 Windows 打包失败，可能需要安装交叉编译工具。在 macOS 上：

```bash
# 安装 mingw-w64（用于 Windows 交叉编译）
brew install mingw-w64
```

### 前端构建失败

```bash
cd client
rm -rf node_modules dist
npm install
npm run build
```

## 开发者注意事项

### 修改版本号

编辑 `scripts/package.sh`，修改：

```bash
VERSION="1.0.0"  # 改为新版本号
```

### 添加新平台

在 `scripts/package.sh` 中的 `PLATFORMS` 数组添加新平台：

```bash
PLATFORMS=(
    "linux/amd64/look-alike/look-alike-linux-x64"
    # ... 其他平台
)
```

### 自定义打包内容

修改 `create_package()` 函数来添加额外的文件或配置。

## CI/CD 集成

推荐在 CI/CD 中使用：

```yaml
# GitHub Actions 示例
- name: Package for all platforms
  run: |
    make install
    make package

- name: Upload artifacts
  uses: actions/upload-artifact@v3
  with:
    name: releases
    path: dist/*.{zip,tar.gz}
```

## 许可证

打包脚本遵循与主项目相同的许可证。
