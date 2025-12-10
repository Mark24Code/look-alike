# 项目删除机制说明

## 删除项目时的操作流程

当用户删除一个项目时，系统会执行以下操作：

### 1. 前端二次确认

用户点击删除按钮后，会弹出确认对话框：
- 显示项目名称
- 警告："此操作将删除所有相关数据且无法恢复"
- 需要用户点击"确认删除"才会执行

### 2. 后端删除流程

#### 2.1 中止后台线程/进程

使用 `ThreadManager.stop_project_threads(project_id)` 中止所有正在运行的后台任务：

- **比较/扫描线程**: 如果项目正在进行图片比较和扫描，线程会被立即终止
- **导出线程**: 如果项目正在导出数据，线程会被立即终止

线程管理器会：
1. 查找该项目的所有活动线程
2. 对每个线程执行 `thread.kill` 强制终止
3. 等待最多2秒让线程清理资源
4. 从线程追踪表中移除记录

#### 2.2 删除数据库记录

调用 `project.destroy` 会级联删除所有相关数据：

**级联删除链**:
```
Project (项目)
  ├─ project_targets (目标列表)          [dependent: :destroy]
  │   └─ comparison_candidates (候选项)  [dependent: :destroy]
  └─ source_files (源文件列表)           [dependent: :destroy]
      ├─ comparison_candidates (候选项)  [dependent: :destroy]
      └─ selection (用户选择)            [dependent: :destroy]
```

**删除顺序**（ActiveRecord 自动处理）:
1. `Selection` 记录（用户的确认选择）
2. `ComparisonCandidate` 记录（所有匹配候选项）
3. `SourceFile` 记录（源文件信息）
4. `ProjectTarget` 记录（目标配置）
5. `Project` 记录（项目本身）

### 3. 删除后的状态

- ✅ 数据库中所有相关记录已删除
- ✅ 所有后台线程/进程已终止
- ✅ 内存中的线程引用已清理
- ⚠️ **磁盘上的原始文件不受影响**（符合设计要求）
- ⚠️ **已导出的文件不受影响**（如果导出已完成）

### 4. ThreadManager 实现细节

#### 线程追踪

```ruby
@threads = {
  1 => {                    # project_id
    comparison: Thread,     # 比较线程
    export: Thread          # 导出线程
  },
  2 => { ... }
}
```

#### 主要方法

- `start_comparison(project_id, &block)`: 启动比较线程，自动停止该项目的旧比较线程
- `start_export(project_id, &block)`: 启动导出线程，自动停止该项目的旧导出线程
- `stop_project_threads(project_id)`: 停止项目的所有线程
- `stop_thread(project_id, type)`: 停止项目的特定类型线程
- `active_threads(project_id)`: 查询项目的活动线程
- `has_active_threads?(project_id)`: 检查项目是否有活动线程

#### 线程安全

- 使用 `Mutex` 确保线程操作的原子性
- 防止竞态条件
- 自动清理已完成的线程引用

### 5. 错误处理

后台线程被终止时：
- 线程内的代码会抛出 `ThreadError` 或直接被终止
- `ensure` 块会执行清理工作
- 错误会被记录到日志
- 不会影响其他项目的线程

### 6. 注意事项

1. **强制终止**: 使用 `thread.kill` 是强制终止，可能导致线程正在进行的操作被中断
2. **资源清理**: 确保服务类中使用 `ensure` 块进行资源清理
3. **文件安全**: 原始图片文件不会被删除，只删除数据库记录
4. **并发安全**: 使用互斥锁保护线程管理器的内部状态

### 7. 未来改进建议

1. **优雅关闭**: 可以考虑添加一个"停止信号"机制，让线程自行检查并优雅退出
2. **进度保存**: 在长时间任务中定期保存进度，以便重启后恢复
3. **任务队列**: 使用专业的后台任务队列（如 Sidekiq）替代原生线程
4. **状态通知**: 通过 WebSocket 实时通知用户线程停止状态
