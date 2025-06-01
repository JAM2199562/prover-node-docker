# ZKWasm Prover Node - Vast.ai Deployment Guide

这个 Docker 镜像专为 vast.ai 部署优化，具有智能配置检测和自动启动功能。

## 🚀 快速开始

### 1. 在 vast.ai 上启动实例

```bash
# 使用你构建的镜像
docker run -d --gpus all --name zkwasm-prover \
  -p 22:22 \
  your-dockerhub-username/zkwasm:latest
```

### 2. SSH 连接到容器

```bash
ssh zkwasm@YOUR_VAST_AI_IP -p 22
# 默认密码: zkwasm
```

### 3. 配置 prover

编辑配置文件：
```bash
cd /home/zkwasm/prover-node-release
nano prover_config.json
```

修改以下字段：
```json
{
  "server_url": "https://rpc.zkwasmhub.com:8090",
  "priv_key": "YOUR_64_CHARACTER_HEX_PRIVATE_KEY"
}
```

**重要说明：**
- `priv_key` 必须是 64 字符的十六进制字符串
- **不要包含** `0x` 前缀
- `server_url` 设置为正确的 prover 服务器地址

### 4. 自动启动

一旦配置正确，prover 将自动检测并启动！

## 📊 监控和日志

### 查看入口脚本日志
```bash
tail -f /home/zkwasm/prover-node-release/logs/entrypoint.log
```

### 查看 prover 日志
```bash
# 查看最新的 prover 日志
ls -la /home/zkwasm/prover-node-release/logs/prover/
tail -f /home/zkwasm/prover-node-release/logs/prover/prover_*.log
```

### 检查进程状态
```bash
# 查看 prover 进程
ps aux | grep zkwasm-playground

# 查看 GPU 使用情况
nvidia-smi
```

## 🔧 故障排除

### 配置检查
智能入口脚本会定期显示配置状态：
- ✅ 配置正确 - prover 自动启动
- ❌ 配置错误 - 显示具体问题

### 常见问题

1. **私钥格式错误**
   ```
   ❌ Private Key: Need configuration
   ```
   - 确保私钥是 64 字符十六进制字符串
   - 不要包含 `0x` 前缀

2. **服务器地址未配置**
   ```
   ❌ Server URL: Need configuration
   ```
   - 将 `server_url` 从 localhost 改为实际服务器地址

3. **内存不足**
   ```
   WARNING: Available memory (XX GB) is less than the recommended 80 GB
   ```
   - 选择内存更大的 vast.ai 实例

### 手动重启
如果需要手动重启 prover：
```bash
# 停止当前进程
pkill -f zkwasm-playground

# 入口脚本会自动重新检测配置并启动
```

## 🎯 预期行为

1. **容器启动** → 智能入口脚本开始运行
2. **配置检查** → 每 30 秒检查一次配置文件
3. **等待配置** → 显示配置状态和说明
4. **检测配置** → 发现正确配置后立即启动
5. **运行挖矿** → prover 开始工作，持续监控进程状态

## 📁 重要文件位置

```
/home/zkwasm/prover-node-release/
├── prover_config.json          # 主配置文件
├── prover_system_config.json   # 系统配置
├── target/release/zkwasm-playground  # prover 二进制文件
├── logs/
│   ├── entrypoint.log         # 入口脚本日志
│   └── prover/                # prover 运行日志
├── workspace/                 # 工作区
└── rocksdb/                   # 数据库目录
```

## 🔐 安全提醒

- 更改默认 SSH 密码
- 不要在日志中暴露私钥
- 定期备份重要配置文件

## 💡 优化建议

1. **选择合适的实例**：
   - GPU: RTX 4090 或更好
   - 内存: 80GB+
   - 存储: 50GB+

2. **监控资源使用**：
   - 定期检查 `nvidia-smi`
   - 监控内存和磁盘使用

3. **日志管理**：
   - 定期清理旧日志文件
   - 监控日志文件大小 