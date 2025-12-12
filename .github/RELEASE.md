# GitHub Actions 自动发布指南

本项目使用 GitHub Actions 自动构建和发布多平台产物。

## 工作流说明

### 1. Release 工作流（`.github/workflows/release.yml`）

**触发条件**：推送版本标签（如 `v1.0.0`）

**构建平台**：
- Windows x64 (`.zip`)
- macOS Intel x64 (`.tar.gz`)
- macOS Apple Silicon ARM64 (`.tar.gz`)

**流程**：
1. 构建前端（Ubuntu）
2. 并行构建三个平台的后端
3. 打包产物
4. 创建 GitHub Release
5. 上传所有平台的构建产物

### 2. CI 工作流（`.github/workflows/ci.yml`）

**触发条件**：Push 到 main/develop 分支或 Pull Request

**检查内容**：
- 前端构建测试
- 后端测试和构建
- Go 代码格式检查
- 跨平台构建测试（Linux/macOS/Windows）

## 如何发布新版本

### 方法一：使用命令行

```bash
# 1. 确保代码已提交
git add .
git commit -m "Release v1.0.0"

# 2. 创建并推送标签
git tag v1.0.0
git push origin v1.0.0

# 3. GitHub Actions 会自动开始构建
# 访问 https://github.com/你的用户名/look-alike/actions 查看进度
```

### 方法二：使用 GitHub 网页界面

1. 访问仓库的 **Releases** 页面
2. 点击 **"Draft a new release"**
3. 在 **"Choose a tag"** 下拉框中输入新版本号（如 `v1.0.1`）
4. 点击 **"Create new tag: v1.0.1 on publish"**
5. 填写 Release 标题和说明
6. 点击 **"Publish release"**

GitHub Actions 会自动构建并上传产物。

### 版本号规范

遵循语义化版本（Semantic Versioning）：

- `v1.0.0` - 主版本.次版本.修订版本
- `v1.0.0-beta.1` - 预发布版本
- `v1.0.0-rc.1` - Release Candidate

示例：
```bash
git tag v1.0.0        # 正式版本
git tag v1.1.0-beta.1 # Beta 版本
git tag v1.1.0-rc.1   # RC 版本
```

## 构建时间

完整的 Release 构建大约需要：
- 前端构建：~2 分钟
- Windows 构建：~3 分钟
- macOS x64 构建：~3 分钟
- macOS ARM64 构建：~3 分钟
- **总计：约 5-8 分钟**（并行构建）

## 查看构建状态

### 实时监控

访问 Actions 页面查看实时构建日志：
```
https://github.com/你的用户名/look-alike/actions
```

### 徽章（Badge）

在 README.md 中添加构建状态徽章：

```markdown
![Release](https://github.com/你的用户名/look-alike/workflows/Release/badge.svg)
![CI](https://github.com/你的用户名/look-alike/workflows/CI/badge.svg)
```

## 自动生成的 Release 内容

Release 会自动包含：

1. **标题**：`Look-Alike v1.0.0`
2. **说明**：
   - 下载指南（根据操作系统）
   - 快速开始说明
   - 主要特性
   - 问题反馈链接
3. **附件**：
   - `look-alike-windows-x64.zip` (约 10 MB)
   - `look-alike-macos-x64.tar.gz` (约 9 MB)
   - `look-alike-macos-arm64.tar.gz` (约 8 MB)

## 常见问题

### Q1: 构建失败怎么办？

1. 检查 Actions 日志找到错误信息
2. 常见原因：
   - 依赖安装失败：检查 `package.json` 和 `go.mod`
   - 构建失败：检查本地是否能正常构建
   - 测试失败：修复测试代码

### Q2: 如何修改 Release 说明？

编辑 `.github/workflows/release.yml` 中的 `Generate release notes` 步骤。

### Q3: 如何添加新的平台？

在 `release.yml` 的 `build-macos` job 的 `matrix` 中添加新平台：

```yaml
strategy:
  matrix:
    include:
      - arch: amd64
        name: macos-x64
      - arch: arm64
        name: macos-arm64
      - arch: amd64
        name: linux-x64  # 新增
```

### Q4: 如何跳过某次构建？

在 commit 消息中添加 `[skip ci]`：

```bash
git commit -m "Update docs [skip ci]"
```

### Q5: 构建产物保留多久？

- **Artifacts**（中间产物）：1 天
- **Release 附件**：永久保留

## 手动触发构建

如果需要手动触发（用于测试），可以修改 workflow：

```yaml
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:  # 添加这一行允许手动触发
```

然后在 Actions 页面点击 **"Run workflow"**。

## 构建缓存

工作流使用了缓存来加速构建：
- **Node.js**：缓存 `node_modules`
- **Go**：缓存 Go 模块

第一次构建较慢，后续构建会快很多。

## 安全注意事项

1. **GITHUB_TOKEN**：自动提供，无需配置
2. **Secrets**：如需其他密钥，在仓库 Settings > Secrets 中添加
3. **权限**：workflow 已配置最小权限（`contents: write`）

## 本地测试

在推送标签前，建议先本地测试构建：

```bash
# 测试前端构建
cd client && npm run build

# 测试后端构建
cd go-server && go build ./cmd/server

# 测试完整打包流程
make package
```

## 更新日志

建议在仓库根目录维护 `CHANGELOG.md`，记录每个版本的变更。

Release 创建后，可以手动编辑 Release 说明来添加详细的更新日志。

## 参考资料

- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)
- [actions/upload-artifact](https://github.com/actions/upload-artifact)
- [Semantic Versioning](https://semver.org/)

---

**提示**：第一次推送标签时，请确保在 GitHub 仓库设置中启用了 Actions：
Settings > Actions > General > Actions permissions > Allow all actions
