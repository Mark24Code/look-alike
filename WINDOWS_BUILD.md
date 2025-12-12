# Windows 交叉编译指南

## 问题说明

在 macOS 或 Linux 上交叉编译 Windows 版本时，由于项目使用了 SQLite（需要 CGO），因此需要 Windows 工具链才能编译。

## 解决方案

### 方案一：安装 mingw-w64（推荐）

#### macOS

```bash
# 使用 Homebrew 安装
brew install mingw-w64
```

安装完成后，验证安装：

```bash
x86_64-w64-mingw32-gcc --version
```

然后重新运行打包：

```bash
make package-windows
# 或
make package  # 打包所有平台
```

#### Linux (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install mingw-w64
```

#### Linux (Fedora/RHEL/CentOS)

```bash
sudo dnf install mingw64-gcc mingw64-gcc-c++
```

### 方案二：仅构建 macOS 版本

如果你只需要 macOS 版本，可以跳过 Windows 构建：

```bash
# 仅构建 macOS Intel
make package-mac-amd64

# 仅构建 macOS ARM64
make package-mac-arm64
```

或者使用脚本直接指定：

```bash
# 构建 macOS Intel
./scripts/package.sh darwin-amd64

# 构建 macOS ARM64
./scripts/package.sh darwin-arm64
```

### 方案三：在 Windows 机器上构建

如果你有 Windows 机器或使用 CI/CD：

1. **在 Windows 机器上**：
   ```bash
   # 安装 Go 和 Node.js
   # 然后运行
   make package-windows
   ```

2. **在 CI/CD 中**（如 GitHub Actions）：
   ```yaml
   - name: Build Windows
     runs-on: windows-latest
     steps:
       - uses: actions/checkout@v3
       - uses: actions/setup-go@v4
       - uses: actions/setup-node@v3
       - run: make install
       - run: make package-windows
   ```

## 自动跳过

打包脚本已经配置为自动检测 mingw-w64：

- ✅ 如果已安装：正常构建 Windows 版本
- ⚠️ 如果未安装：跳过 Windows 构建，继续构建其他平台

这意味着即使没有 mingw-w64，你仍然可以成功构建 macOS 版本。

## 验证

安装 mingw-w64 后，可以验证是否能正常工作：

```bash
# 清理之前的构建
make clean

# 重新构建所有平台
make package
```

成功的输出应该显示：

```
✓ All packages built successfully (3/3)

Generated packages:
  dist/look-alike-windows-x64.zip (xxx)
  dist/look-alike-macos-x64.tar.gz (xxx)
  dist/look-alike-macos-arm64.tar.gz (xxx)
```

## 常见问题

### Q: 为什么需要 mingw-w64？

A: 项目使用了 SQLite 数据库，Go 的 SQLite 驱动（`github.com/mattn/go-sqlite3`）使用了 CGO（C 语言绑定）。在非 Windows 平台上编译 Windows 版本时，需要 Windows 工具链来编译 C 代码。

### Q: 能否使用纯 Go 的 SQLite 驱动？

A: 可以，但需要修改代码。纯 Go 驱动（如 `modernc.org/sqlite`）性能略低，但不需要 CGO，更容易交叉编译。如果你经常需要交叉编译，可以考虑切换到纯 Go 驱动。

### Q: mingw-w64 安装失败怎么办？

A:
1. 确保 Homebrew 是最新版本：`brew update`
2. 如果仍然失败，尝试：`brew reinstall mingw-w64`
3. 或者使用方案二/三，不编译 Windows 版本

### Q: 构建的 Windows 版本能在所有 Windows 上运行吗？

A: 是的，构建的 `.exe` 是 64 位 Windows 可执行文件，支持 Windows 7 及以上版本（需要 64 位系统）。

## 安装时间

- macOS (brew install): 约 2-5 分钟
- Linux (apt-get): 约 1-3 分钟

安装一次后，后续构建无需重新安装。
