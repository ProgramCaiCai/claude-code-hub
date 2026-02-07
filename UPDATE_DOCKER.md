# Docker 部署更新指南

本文档说明如何在服务器上更新 Docker 部署的 Claude Code Hub 到最新代码。

## 快速开始

### 基本用法

```bash
# 在项目根目录执行
./update-docker.sh -d /www/compose/claude-code-hub
```

### 常用选项

```bash
# 查看帮助
./update-docker.sh --help

# 指定部署目录
./update-docker.sh -d /path/to/deployment

# 指定构建平台（适用于跨平台构建）
./update-docker.sh -d /www/compose/claude-code-hub -p linux/amd64

# 不使用缓存构建（强制重新构建所有层）
./update-docker.sh -d /www/compose/claude-code-hub --no-cache

# 跳过 git pull（使用当前代码）
./update-docker.sh -d /www/compose/claude-code-hub --skip-pull
```

## 工作流程

脚本会自动执行以下步骤：

1. **检查部署目录** - 验证目录存在且包含 `docker-compose.yaml`
2. **拉取最新代码** - 从 git 仓库拉取最新代码（可用 `--skip-pull` 跳过）
3. **构建 Docker 镜像** - 使用 `deploy/Dockerfile` 本地构建镜像
4. **更新 compose 配置** - 修改 `docker-compose.yaml` 使用本地镜像
5. **重启服务** - 停止并重新启动所有服务
6. **健康检查** - 等待服务变为健康状态（最多 60 秒）

## 注意事项

### 部署目录

- 部署目录必须是通过 `deploy.sh` 创建的目录
- 目录中必须包含 `docker-compose.yaml` 文件
- 常见路径：
  - Linux: `/www/compose/claude-code-hub`
  - macOS: `~/Applications/claude-code-hub`

### 镜像标签

- 脚本会构建名为 `claude-code-hub:local` 的本地镜像
- 首次运行时会自动备份原始 `docker-compose.yaml` 为 `docker-compose.yaml.backup`
- 后续更新会使用本地镜像，不再从 GitHub 拉取

### 构建平台

如果在不同架构的机器上构建，需要指定平台：

```bash
# x86_64 架构
./update-docker.sh -d /www/compose/claude-code-hub -p linux/amd64

# ARM64 架构
./update-docker.sh -d /www/compose/claude-code-hub -p linux/arm64
```

### 版本号

- 脚本会自动读取项目根目录的 `VERSION` 文件
- 版本号会作为构建参数传递给 Docker（`APP_VERSION`）
- 如果 `VERSION` 文件不存在，默认使用 `dev`

## 故障排查

### 服务未变为健康状态

如果服务在 60 秒内未变为健康状态：

```bash
# 查看应用日志
cd /www/compose/claude-code-hub
docker compose logs -f app

# 查看所有服务日志
docker compose logs -f
```

### 构建失败

```bash
# 清理 Docker 缓存后重试
docker system prune -a
./update-docker.sh -d /www/compose/claude-code-hub --no-cache
```

### 回滚到原始配置

如果需要回滚到使用 GitHub 镜像：

```bash
cd /www/compose/claude-code-hub
cp docker-compose.yaml.backup docker-compose.yaml
docker compose down
docker compose pull
docker compose up -d
```

## 与 deploy.sh 的区别

| 特性 | deploy.sh | update-docker.sh |
|------|-----------|------------------|
| 用途 | 首次部署 | 更新现有部署 |
| 镜像来源 | GitHub Registry | 本地构建 |
| 是否构建代码 | 否 | 是 |
| 配置文件 | 创建新的 | 修改现有的 |
| 数据库/Redis | 创建新实例 | 使用现有实例 |

## 示例场景

### 场景 1：日常更新

```bash
# 1. SSH 到服务器
ssh user@server

# 2. 进入项目目录
cd /path/to/claude-code-hub

# 3. 执行更新
./update-docker.sh -d /www/compose/claude-code-hub

# 4. 查看日志确认
cd /www/compose/claude-code-hub
docker compose logs -f app
```

### 场景 2：测试本地修改

```bash
# 1. 修改代码后，不拉取远程更新
./update-docker.sh -d /www/compose/claude-code-hub --skip-pull

# 2. 如果需要完全重新构建
./update-docker.sh -d /www/compose/claude-code-hub --skip-pull --no-cache
```

### 场景 3：跨架构部署

```bash
# 在 ARM64 机器上构建 x86_64 镜像
./update-docker.sh -d /www/compose/claude-code-hub -p linux/amd64
```

## 相关命令

```bash
# 查看运行中的容器
docker compose ps

# 重启单个服务
docker compose restart app

# 查看资源使用情况
docker stats

# 清理未使用的镜像
docker image prune -a
```
