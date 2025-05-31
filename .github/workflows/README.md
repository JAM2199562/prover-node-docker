# GitHub Actions Workflows

本目录包含两个 GitHub Actions workflows，用于自动构建和推送 zkwasm Docker 镜像到 Docker Hub。

## Workflows 说明

### 1. build-and-push.yml
- **功能**: 使用 Docker Buildx 直接构建和推送镜像
- **特点**: 
  - 支持多平台构建
  - 使用 GitHub Actions 缓存优化构建速度
  - 自动生成标签和元数据
  - 支持语义化版本标签

### 2. build-with-script.yml
- **功能**: 使用项目原有的 `build_image.sh` 脚本构建镜像
- **特点**: 
  - 保持与本地构建的一致性
  - 在 CI 环境中自动跳过 GPU 检查
  - 简单直接的构建流程

## 配置步骤

### 1. 设置 Docker Hub Secrets

在你的 GitHub 仓库中设置以下 Secrets：

1. 前往 GitHub 仓库的 `Settings` > `Secrets and variables` > `Actions`
2. 添加以下 Repository secrets：
   - `DOCKERHUB_USERNAME`: 你的 Docker Hub 用户名
   - `DOCKERHUB_TOKEN`: 你的 Docker Hub Access Token

### 2. 创建 Docker Hub Access Token

1. 登录 [Docker Hub](https://hub.docker.com/)
2. 前往 `Account Settings` > `Security` > `Access Tokens`
3. 点击 `New Access Token`
4. 输入描述（如 "GitHub Actions"）
5. 选择权限：`Read, Write, Delete`
6. 生成并复制 token

### 3. 配置分支保护（可选）

建议为 `main` 或 `master` 分支设置保护规则，确保只有通过 CI 测试的代码才能合并。

## 触发条件

### 自动触发
- **推送到主分支**: 构建并推送镜像
- **推送标签**: 构建并推送带版本号的镜像
- **Pull Request**: 仅构建测试，不推送

### 手动触发
- 在 Actions 页面可以手动触发 workflow

## 镜像标签

构建的镜像将推送到以下位置：
- `<你的用户名>/zkwasm:latest` - 主分支的最新版本
- `<你的用户名>/zkwasm:<commit-sha>` - 特定提交的版本
- `<你的用户名>/zkwasm:<tag>` - 标签版本（如果推送了 git tag）

## 使用构建的镜像

在其他机器上使用构建好的镜像：

```bash
# 拉取最新镜像
docker pull <你的用户名>/zkwasm:latest

# 更新 docker-compose.yml 中的镜像名
# 将 `image: zkwasm:latest` 改为 `image: <你的用户名>/zkwasm:latest`

# 运行服务
docker-compose up -d
```

## 故障排除

### 常见问题

1. **权限错误**: 确保 DOCKERHUB_TOKEN 有正确的读写权限
2. **分支名不匹配**: 检查你的主分支是 `main` 还是 `master`
3. **镜像构建失败**: 查看 Actions 日志了解具体错误信息

### 调试步骤

1. 检查 Actions 页面的构建日志
2. 验证 Secrets 是否正确设置
3. 确认 Docker Hub 仓库权限 