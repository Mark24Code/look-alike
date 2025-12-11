# Rake 任务快速参考

## 常用命令

```bash
# 列出所有项目
bundle exec rake project:list

# 查看项目状态
bundle exec rake project:status[1]

# 重置所有数据（⚠️ 危险操作）
bundle exec rake project:reset

# 删除指定项目
bundle exec rake project:delete[1]

# 快速创建项目
bundle exec rake project:quick_init[test,/path/to/source,de,/path/de,ta,/path/ta]

# 交互式创建项目
bundle exec rake project:init
```

## 推荐工作流

### 使用 API（推荐）

```bash
# 1. 确保服务器运行
ruby app.rb

# 2. 通过 API 创建项目
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

# 3. 查看进度
bundle exec rake project:status[1]
```

详细文档请查看 [RAKE_TASKS.md](./RAKE_TASKS.md)
