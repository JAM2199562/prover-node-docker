# ZKWasm 外部 FTP 服务器部署指南

## 🎯 **解决方案概述**

使用分离的 FTP 服务器提供参数文件，prover 容器从外部 FTP 服务器下载所需的参数文件。

```
┌─────────────────┐       FTP Download        ┌─────────────────┐
│   FTP Server    │ ◄─────────────────────── │  Prover Node    │
│  (外部机器)      │     K22.params etc.      │   (vast.ai)     │
│  Port 21        │    (Active Mode FTP)     │                 │
└─────────────────┘                          └─────────────────┘
```

## 🚀 **1. 部署外部 FTP 服务器**

### **在有 GPU 的机器上启动 FTP 服务器**

```bash
# 克隆项目
git clone <your-repo>
cd prover-node-docker

# 启动独立的 FTP 服务器（按原始设计）
# 注意：PUBLICHOST 已设置为 "0.0.0.0"，支持外部访问
docker-compose -f docker-compose-ftp.yml up -d

# 检查服务状态
docker-compose -f docker-compose-ftp.yml ps
```

### **验证 FTP 服务器**

```bash
# 测试 FTP 连接（主动模式）
ftp YOUR_FTP_SERVER_IP
# 用户名: ftpuser
# 密码: ftppassword

# 或使用 wget 测试（wget默认使用主动模式）
wget -r -nH -nv --cut-dirs=1 --no-parent \
    --user=ftpuser --password=ftppassword \
    ftp://YOUR_FTP_SERVER_IP/params/ \
    -P /tmp/test/

# 检查是否下载到参数文件
ls -la /tmp/test/params/

# 🎯 快速测试：检查FTP服务器是否正常响应
telnet YOUR_FTP_SERVER_IP 21
# 看到 "220 Welcome to Pure-FTPd" 表示成功
```

## 🔧 **2. 配置 Prover 节点**

### **方案A: 使用不同的SSH端口（推荐）**

```bash
# 启动 prover 容器，SSH 使用 2222 端口避免冲突
docker run -d --gpus all \
    -e FTP_SERVER_IP="YOUR_FTP_SERVER_IP" \
    -p 2222:22 \
    --name zkwasm-prover \
    your-dockerhub-username/zkwasm:latest
```

### **方案B: 不暴露SSH端口（更简洁）**

```bash
# 如果不需要SSH访问，可以完全不暴露SSH端口
docker run -d --gpus all \
    -e FTP_SERVER_IP="YOUR_FTP_SERVER_IP" \
    --name zkwasm-prover \
    your-dockerhub-username/zkwasm:latest

# 查看日志方式
docker logs -f zkwasm-prover
```

### **方案C: 使用 docker exec 访问容器**

```bash
# 不映射SSH端口，直接使用 docker exec 进入容器
docker run -d --gpus all \
    -e FTP_SERVER_IP="YOUR_FTP_SERVER_IP" \
    --name zkwasm-prover \
    your-dockerhub-username/zkwasm:latest

# 需要进入容器时
docker exec -it zkwasm-prover bash
```

### **配置文件设置**

#### **如果使用方案A（SSH端口2222）：**
```bash
ssh zkwasm@YOUR_HOST_IP -p 2222
# 密码: zkwasm
```

#### **如果使用方案B/C（无SSH端口）：**
```bash
# 直接进入容器
docker exec -it zkwasm-prover bash

# 然后编辑配置
cd /home/zkwasm/prover-node-release
nano prover_config.json
```

设置正确的私钥和服务器：
```json
{
  "server_url": "https://rpc.zkwasmhub.com:8090",
  "priv_key": "YOUR_64_CHARACTER_HEX_PRIVATE_KEY_WITHOUT_0X"
}
```

## 📊 **3. 启动和监控**

### **启动挖矿**

```bash
# 容器会自动：
# 1. 检查配置文件
# 2. 从外部 FTP 服务器下载参数文件  
# 3. 启动 zkwasm prover

# 如果需要手动重启
docker restart zkwasm-prover
```

### **监控日志**

#### **方案A（有SSH端口）：**
```bash
# SSH 进入容器
ssh zkwasm@YOUR_HOST_IP -p 2222

# 查看日志
tail -f /home/zkwasm/prover-node-release/logs/entrypoint.log
tail -f /home/zkwasm/prover-node-release/logs/prover/*.log
```

#### **方案B/C（无SSH端口）：**
```bash
# 直接查看 Docker 日志
docker logs -f zkwasm-prover

# 或进入容器查看详细日志
docker exec -it zkwasm-prover tail -f /home/zkwasm/prover-node-release/logs/entrypoint.log
docker exec -it zkwasm-prover tail -f /home/zkwasm/prover-node-release/logs/prover/*.log
```

### **检查状态**

```bash
# 检查容器状态
docker ps | grep zkwasm-prover

# 进入容器检查进程
docker exec -it zkwasm-prover ps aux | grep zkwasm-playground

# 检查参数文件
docker exec -it zkwasm-prover ls -la /home/zkwasm/prover-node-release/workspace/static/params/

# 检查网络连接
docker exec -it zkwasm-prover ping YOUR_FTP_SERVER_IP
docker exec -it zkwasm-prover telnet YOUR_FTP_SERVER_IP 21
```

## 🛠️ **4. 故障排除**

### **常见问题**

1. **无法连接 FTP 服务器**
   ```bash
   # 检查网络连通性
   docker exec -it zkwasm-prover ping YOUR_FTP_SERVER_IP
   docker exec -it zkwasm-prover telnet YOUR_FTP_SERVER_IP 21
   
   # 检查防火墙设置
   # 只需要确保 21 端口开放（主动模式FTP）
   ```

2. **参数文件下载失败**
   ```bash
   # 手动测试下载（确保使用主动模式）
   docker exec -it zkwasm-prover wget -r -nH -nv --cut-dirs=1 --no-parent \
       --user=ftpuser --password=ftppassword \
       ftp://YOUR_FTP_SERVER_IP/params/ \
       -P /tmp/test/
   ```

3. **配置文件问题**
   ```bash
   # 验证 JSON 格式
   docker exec -it zkwasm-prover cat /home/zkwasm/prover-node-release/prover_config.json | jq .
   
   # 检查私钥格式 (应该是64位十六进制，无0x前缀)
   echo "YOUR_PRIVATE_KEY" | wc -c  # 应该是65 (64字符+换行)
   ```

## 🔐 **5. 安全建议**

### **FTP 服务器安全**

- 只在内网环境部署 FTP 服务器
- 使用强密码 (可修改 docker-compose-ftp.yml 中的密码)
- 考虑使用 VPN 连接

### **防火墙配置**

```bash
# FTP 服务器需要开放的端口（主动模式）
- 21 (FTP控制端口，也用于数据传输)

# Prover 只需要出站连接到 FTP 服务器的21端口
# 如果使用SSH，还需要开放对应的SSH端口（如2222）
```

## 📋 **6. 环境变量参考**

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `FTP_SERVER_IP` | `localhost` | FTP 服务器 IP 地址 |
| `CUDA_VISIBLE_DEVICES` | `0` | GPU 设备 ID |
| `RUST_LOG` | `info` | 日志级别 |

## 🎉 **优势总结**

✅ **架构清晰**: FTP 服务器和 Prover 完全分离  
✅ **部署灵活**: FTP 服务器可部署在任何有参数文件的机器上  
✅ **保密性好**: 使用现有用户名密码，只需配置 IP 地址  
✅ **维护简单**: 各组件独立，便于调试和升级  
✅ **成本优化**: FTP 服务器不需要昂贵的 GPU 资源  
✅ **端口友好**: 只需要开放21端口（主动模式FTP） 