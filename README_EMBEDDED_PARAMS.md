# ZKWasm Prover Node - 内置参数文件架构

## 🎯 **解决方案概述**

使用多阶段 Docker 构建，在镜像构建时直接从 `zkwasm/params` 镜像中拷贝参数文件，避免运行时网络下载问题。

```
┌─────────────────────┐    Build Time Copy    ┌─────────────────────┐
│   zkwasm/params     │ ──────────────────► │   zkwasm:latest     │
│   (Source Image)    │   K22.params etc.    │   (Built-in Params) │
└─────────────────────┘                       └─────────────────────┘
```

## 🚀 **架构优势**

✅ **无网络依赖**: 参数文件在构建时内置，运行时无需网络下载  
✅ **简化部署**: 只需一个容器，无需外部 FTP 服务器  
✅ **更高可靠性**: 避免网络连接问题和防火墙限制  
✅ **更快启动**: 跳过下载步骤，直接验证本地文件  
✅ **版本一致性**: 参数文件版本与镜像版本绑定  

## 🔧 **构建和部署**

### **1. 构建镜像**

```bash
# 构建包含内置参数文件的镜像
bash scripts/build_image.sh

# 镜像构建过程中会：
# 1. 从 zkwasm/params 镜像中拷贝参数文件
# 2. 将文件放置在 /home/zkwasm/prover-node-release/workspace/static/params/
# 3. 设置正确的文件权限
```

### **2. 启动服务**

```bash
# 启动 prover 节点（无需外部依赖）
bash scripts/start.sh

# 或者使用 docker compose 直接启动
docker compose up
```

### **3. 配置私钥**

编辑 `prover_config.json` 文件：

```json
{
  "server_url": "https://rpc.zkwasmhub.com:8090",
  "priv_key": "YOUR_64_CHARACTER_HEX_PRIVATE_KEY_WITHOUT_0X"
}
```

## 📊 **监控和日志**

### **检查参数文件**

```bash
# 进入容器检查参数文件
docker exec -it prover-node-docker-prover-node-1 bash
cd /home/zkwasm/prover-node-release
ls -la workspace/static/params/

# 预期输出:
# K22.params     (~268MB)
# K23.params     (~537MB)
# backup_K22.params
# backup_K23.params
```

### **查看日志**

```bash
# 查看容器日志
docker logs -f prover-node-docker-prover-node-1

# 查看详细 prover 日志
docker exec -it prover-node-docker-prover-node-1 tail -f logs/prover/*.log
```

## 🛠️ **故障排除**

### **常见问题**

1. **参数文件未找到**
   ```bash
   # 错误信息: "Parameter files not found in workspace/static/params/"
   # 解决方案: 重新构建镜像
   bash scripts/build_image.sh
   ```

2. **构建失败**
   ```bash
   # 确保能访问 zkwasm/params 镜像
   docker pull zkwasm/params
   
   # 检查多阶段构建是否成功
   docker build --no-cache -t zkwasm .
   ```

3. **权限问题**
   ```bash
   # 检查文件权限
   docker exec -it container_name ls -la workspace/static/params/
   
   # 权限应该是: zkwasm:root
   ```

## 🔄 **迁移指南**

### **从外部 FTP 架构迁移**

如果你之前使用外部 FTP 服务器：

1. **停止旧服务**
   ```bash
   docker compose -f docker-compose-ftp.yml down
   docker compose down
   ```

2. **重新构建镜像**
   ```bash
   bash scripts/build_image.sh
   ```

3. **使用新的简化配置启动**
   ```bash
   bash scripts/start.sh
   ```

4. **验证参数文件**
   ```bash
   docker exec -it prover-node-docker-prover-node-1 ls -la workspace/static/params/
   ```

## 📋 **技术细节**

### **Dockerfile 多阶段构建**

```dockerfile
# 第一阶段: 从 zkwasm/params 提取参数文件
FROM zkwasm/params as params-source

# 第二阶段: 主构建
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04
# ... 其他构建步骤 ...

# 拷贝参数文件
COPY --from=params-source /home/ftpuser/params/* /home/zkwasm/prover-node-release/workspace/static/params/
```

### **智能入口脚本验证**

```bash
# 脚本会验证:
# 1. 参数目录是否存在
# 2. 参数文件是否非空
# 3. 文件权限是否正确
```

## 🎉 **总结**

这个新架构通过在构建时内置参数文件，完全消除了网络下载的复杂性和不可靠性。部署更简单、启动更快、运行更稳定。 