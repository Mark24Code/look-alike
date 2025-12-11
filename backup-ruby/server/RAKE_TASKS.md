# Project Management Rake Tasks

管理图片对比项目的 Rake 任务工具集。

## 📋 可用命令

### 1. 列出所有项目

```bash
bundle exec rake project:list
```

显示所有项目的摘要信息，包括 ID、名称、状态和处理进度。

**示例输出：**
```
📋 Projects:

ID    Name                 Status          Progress
-------------------------------------------------------
1     test                 completed       40/40
```

---

### 2. 查看项目状态

```bash
bundle exec rake project:status[PROJECT_ID]
```

显示指定项目的详细信息，包括：
- 项目名称和 ID
- 处理状态
- Source 和 Target 路径
- 文件数量
- 处理时长
- 统计信息（候选项、确认数）

**示例：**
```bash
bundle exec rake project:status[1]
```

**查看所有项目：**
```bash
bundle exec rake project:status
```

---

### 3. 快速创建项目

```bash
bundle exec rake project:quick_init[名称,源路径,目标1名称,目标1路径,目标2名称,目标2路径]
```

快速创建项目并启动后台处理（需要服务器运行）。

**示例：**
```bash
bundle exec rake project:quick_init[test,/Users/bilibili/Labspace/compare-image/source,de,/Users/bilibili/Labspace/compare-image/target_de,ta,/Users/bilibili/Labspace/compare-image/target_ta]
```

**⚠️ 重要：** 后台处理需要 Sinatra 服务器运行在 4567 端口。如果服务器未运行，请先启动：
```bash
ruby app.rb
```

---

### 4. 交互式创建项目

```bash
bundle exec rake project:init
```

启动交互式向导，按提示输入：
- 项目名称
- Source 路径
- 一个或多个 Target（名称和路径）

**示例流程：**
```
🚀 Project Initialization Wizard
==================================================

Project name: my_project
Source path: /path/to/source

Target #1
  Name (or press Enter to finish): de
  Path: /path/to/target_de

Target #2
  Name (or press Enter to finish): ta
  Path: /path/to/target_ta

Target #3
  Name (or press Enter to finish):

==================================================
Summary:
  Project name: my_project
  Source path: /path/to/source
  Target (de): /path/to/target_de
  Target (ta): /path/to/target_ta

Create this project? (y/N): y
```

---

### 5. 删除项目

```bash
bundle exec rake project:delete[PROJECT_ID]
```

删除指定项目及其所有相关数据（source files、target files、candidates、selections）。

**示例：**
```bash
bundle exec rake project:delete[1]
```

**输出：**
```
🗑️  Deleting project: test (ID: 1)
✅ Project deleted successfully!
```

---

### 6. 重置所有项目

```bash
bundle exec rake project:reset
```

**⚠️ 警告：** 此命令会删除数据库中的所有项目和相关数据，谨慎使用！

此命令会：
- 停止所有后台处理线程
- 删除所有对比候选项
- 删除所有选择记录
- 删除所有 source files
- 删除所有 target files
- 删除所有项目目标
- 删除所有项目
- 重置数据库自增计数器

**示例：**
```bash
bundle exec rake project:reset
```

**输出：**
```
🔄 Resetting all projects...
Stopping all background threads...
Clearing comparison candidates...
Clearing selections...
Clearing source files...
Clearing target files...
Clearing project targets...
Clearing projects...
✅ All projects have been reset!

Statistics:
  Projects: 0
  Source Files: 0
  Target Files: 0
  Comparison Candidates: 0
```

---

## 🔧 常见工作流

### 从零开始创建项目

1. **（可选）重置现有数据：**
   ```bash
   bundle exec rake project:reset
   ```

2. **确保服务器运行：**
   ```bash
   ruby app.rb
   # 或在另一个终端
   ```

3. **创建新项目：**
   ```bash
   # 方式 1：快速创建
   bundle exec rake project:quick_init[test,/path/to/source,de,/path/to/de,ta,/path/to/ta]

   # 方式 2：交互式创建
   bundle exec rake project:init

   # 方式 3：通过 API（推荐）
   curl -X POST http://localhost:4567/api/projects \
     -H "Content-Type: application/json" \
     -d '{
       "name": "test",
       "source_path": "/path/to/source",
       "targets": [
         {"name": "de", "path": "/path/to/de"},
         {"name": "ta", "path": "/path/to/ta"}
       ]
     }'
   ```

4. **监控进度：**
   ```bash
   # 查看特定项目
   bundle exec rake project:status[1]

   # 或列出所有项目
   bundle exec rake project:list

   # 或通过 API
   curl http://localhost:4567/api/projects/1
   ```

5. **查看结果：**
   ```
   在浏览器中打开：http://localhost:5173/projects/1/compare
   ```

---

### 清理旧项目

1. **列出所有项目：**
   ```bash
   bundle exec rake project:list
   ```

2. **删除特定项目：**
   ```bash
   bundle exec rake project:delete[1]
   ```

3. **或重置所有：**
   ```bash
   bundle exec rake project:reset
   ```

---

## 💡 使用技巧

1. **使用绝对路径** - 所有目录路径都应该是绝对路径
2. **先验证路径** - 创建项目前确保路径存在
3. **监控后台处理** - 使用 `project:status` 命令监控进度
4. **检查日志** - 如果处理卡住，检查服务器日志
5. **开发/测试时使用 reset** - 需要清空数据时使用 `project:reset`
6. **服务器必须运行** - 后台处理需要 Sinatra 服务器（`ruby app.rb`）在运行

---

## ⚠️ 注意事项

### Rake 任务 vs API

- **Rake 任务**：适合手动管理和测试，但后台线程依赖于 Sinatra 服务器进程
- **API**：推荐用于生产环境，后台处理更稳定

**推荐方式：**
```bash
# 使用 API 创建项目（推荐）
curl -X POST http://localhost:4567/api/projects \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test",
    "source_path": "/Users/bilibili/Labspace/compare-image/source",
    "targets": [
      {"name": "de", "path": "/Users/bilibili/Labspace/compare-image/target_de"},
      {"name": "ta", "path": "/Users/bilibili/Labspace/compare-image/target_ta"}
    ]
  }'
```

### 后台处理说明

使用 Rake 任务创建项目时，后台处理线程会在服务器进程中启动。请确保：
1. Sinatra 服务器正在运行（`ruby app.rb`）
2. 服务器监听在 4567 端口
3. 不要停止服务器，否则处理会中断

---

## 🐛 故障排除

### 项目卡在 "processing" 状态

检查服务器日志并使用 `project:status[ID]` 查看是否有错误信息。如需重新处理，可以删除后重新创建项目。

### 后台处理未启动

确保 Sinatra 服务器在 4567 端口运行。使用 API 而不是 Rake 任务创建项目会更稳定。

### 路径未找到错误

确保所有路径都使用绝对路径（以 `/` 开头），并且目录存在且可访问。

### 数据库锁定错误

如果遇到 SQLite 锁定错误，停止所有正在运行的后台任务，然后重试。
