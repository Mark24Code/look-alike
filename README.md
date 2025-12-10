# Look Alike

一个图片相似度比对工具，用于查找和匹配相似的图片。

## 项目结构

```
look-alike/
├── client/         # 前端项目 (React + Vite)
└── server/         # 后端服务 (Ruby + Sinatra)
```

## 技术栈

### 前端
- React 19
- TypeScript
- Vite
- Ant Design
- React Router

### 后端
- Ruby
- Sinatra
- SQLite
- ActiveRecord

## 快速启动（推荐）

### 使用 Rake 命令启动

**开发模式（推荐开发时使用）：**
```bash
rake start:dev
```
这会同时启动前端开发服务器（5174端口）和后端服务（4568端口），支持热重载。

**生产模式（推荐生产环境使用）：**
```bash
rake start:prod
```
这会自动构建前端（如果未构建）并启动后端服务（4568端口），后端会提供前端静态文件。

**查看所有可用命令：**
```bash
rake help
```

## 开发环境启动（手动方式）

如果你不使用 rake 命令，也可以手动启动：

### 1. 安装依赖

你可以使用 rake 命令快速安装：
```bash
rake install
```

或者手动安装：

**后端依赖：**
```bash
cd server
bundle install
```

**前端依赖：**
```bash
cd client
npm install
```

### 2. 数据库初始化

你可以使用 rake 命令：
```bash
rake db:setup
```

或者手动执行：
```bash
cd server
bundle exec rake db:migrate
```

### 3. 启动开发服务器

**启动后端服务（端口 4568）：**
```bash
cd server
ruby app.rb
```

**启动前端开发服务器（端口 5174）：**
```bash
cd client
npm run dev
```

然后在浏览器中访问：http://localhost:5174

## 生产环境运行

### 1. 构建前端

```bash
cd client
npm run build
```

### 2. 启动后端服务（生产模式）

后端会自动提供前端构建的静态文件：

```bash
cd server
ruby app.rb
```

然后在浏览器中访问：http://localhost:4568

> **注意：** 在生产模式下，所有请求（除 `/api/*` 外）都会被路由到前端应用。

## API 端口配置

- **前端开发服务器端口**: 5174
- **后端服务端口**: 4568

## 其他 Rake 命令

### 数据库管理
```bash
rake db:setup       # 初始化数据库
rake db:reset       # 重置数据库
rake db:migrate     # 运行迁移
rake db:rollback    # 回滚迁移
rake db:status      # 查看迁移状态
```

### 启动服务
```bash
rake start:dev      # 开发模式（前端+后端）
rake start:prod     # 生产模式（后端提供前端静态文件）
rake start:server   # 仅启动后端
rake start:client   # 仅启动前端
```

### 构建和安装
```bash
rake build:client   # 构建前端生产版本
rake install        # 安装所有依赖
rake install:server # 安装后端依赖
rake install:client # 安装前端依赖
```

### 清理
```bash
rake clean          # 清理临时文件
```

## 常见问题

### 生产模式下提示 "Frontend assets not found"

这表示前端资源还未构建，请先运行：

```bash
cd client
npm run build
```

### 端口被占用

如果端口被占用，可以在以下文件中修改端口配置：

- 前端端口：`client/vite.config.ts`
- 后端端口：`server/app.rb`
