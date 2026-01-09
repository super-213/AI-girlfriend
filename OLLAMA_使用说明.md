# Ollama 本地模型使用说明

## 1. 安装 Ollama

访问 [https://ollama.com](https://ollama.com) 下载并安装 Ollama。

macOS 安装命令：
```bash
brew install ollama
```

或直接从官网下载安装包。

## 2. 启动 Ollama 服务

安装完成后，Ollama 会自动在后台运行。如果没有运行，可以手动启动：

```bash
ollama serve
```

默认服务地址：`http://localhost:11434`

## 3. 下载模型

在终端执行以下命令下载模型：

```bash
# 下载 Llama 3.2（推荐，约 2GB）
ollama pull llama3.2

# 下载 Qwen 2.5（中文优化，约 4.7GB）
ollama pull qwen2.5

# 下载 Gemma 2（Google 模型，约 5.4GB）
ollama pull gemma2
```

查看已下载的模型：
```bash
ollama list
```

## 4. 在应用中配置

1. 打开应用的偏好设置
2. 选择"模型设置"标签
3. 在"选择平台"中选择"Ollama 本地"
4. 配置以下参数：
   - **模型**：填写已下载的模型名称
     - 使用 `qwen2.5` 或 `qwen2.5:latest` （推荐，中文对话效果好）
     - 或使用 `llama3` 或 `llama3:latest` （英文对话效果好）
   - **API 地址**：保持默认 `http://localhost:11434/api/chat`
   - **API Key**：无需填写（Ollama 本地模型不需要 API Key）
5. 点击"保存"

**注意**：
- 模型名称可以带或不带 `:latest` 后缀，两种格式都支持
- 例如：`qwen2.5` 和 `qwen2.5:latest` 都可以
- 如果使用特定版本标签，如 `qwen2.5:7b`，也是支持的

## 5. 常用模型推荐

| 模型名称 | 大小 | 特点 | 适用场景 |
|---------|------|------|---------|
| qwen2.5 | ~4.7GB | 中文优化 | 中文对话、理解能力强 |
| llama3 | ~4.7GB | Meta 出品 | 英文对话、通用场景 |
| llama3.2 | ~2GB | 轻量快速 | 日常对话、快速响应 |
| gemma2 | ~5.4GB | Google 出品 | 综合能力强 |
| mistral | ~4.1GB | 平衡性能 | 通用场景 |

**推荐使用 `qwen2.5`**：你已经安装了这个模型，它对中文支持非常好，非常适合与布偶熊·觅语对话！

## 6. 测试模型

在终端测试模型是否正常工作：

```bash
ollama run llama3.2
```

输入问题测试，按 `/bye` 退出。

## 7. 常见问题

### Q: 模型下载很慢怎么办？
A: 可以使用国内镜像或者在网络较好的时候下载。

### Q: 应用无法连接到 Ollama？
A: 检查 Ollama 服务是否运行：
```bash
curl http://localhost:11434/api/tags
```

### Q: 如何删除不需要的模型？
A: 使用命令：
```bash
ollama rm 模型名称
```

### Q: 模型响应速度慢？
A: 
- 选择更小的模型（如 llama3.2）
- 确保电脑有足够的内存
- 关闭其他占用资源的应用

## 8. 优势

✅ **完全本地运行**：数据不会上传到云端，保护隐私  
✅ **无需 API Key**：不需要注册账号或付费  
✅ **离线可用**：没有网络也能使用  
✅ **响应快速**：本地推理，无网络延迟  
✅ **免费使用**：所有模型完全免费  

## 9. 更多信息

- Ollama 官网：https://ollama.com
- 模型库：https://ollama.com/library
- GitHub：https://github.com/ollama/ollama
