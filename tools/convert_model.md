# 模型转换指南

OpenAgent 使用 MNN-LLM 格式的模型。本文档说明如何将 HuggingFace/ModelScope 上的原始模型转换为 App 可用的 MNN 格式。

## 方式一：直接下载官方预转换模型（推荐）

MNN 官方已在魔搭社区提供转换并量化好的模型，无需自行转换：

1. 访问 https://modelscope.cn/organization/MNN
2. 选择所需模型（如 `Qwen3-0.6B-Instruct-MNN`）
3. 下载整个模型目录

模型目录应包含：
```
Qwen3-0.6B-MNN/
├── config.json          # 运行时配置
├── embeddings_bf16.bin  # embedding 权重
├── llm.mnn              # 模型结构
├── llm.mnn.weight       # 模型权重（量化后）
├── llm_config.json      # 模型超参
└── tokenizer.txt        # 分词器
```

推送到设备：
```bash
adb push Qwen3-0.6B-MNN /sdcard/models/Qwen3-0.6B-MNN
```

## 方式二：自行转换模型

适用于官方未提供的模型，或需要自定义量化级别。

### 环境准备

```bash
# 克隆 MNN 源码
git clone https://github.com/alibaba/MNN.git
cd MNN

# 安装 Python 依赖
pip install -r transformers/llm/export/requirements.txt
# 需要 torch、transformers、onnx 等
```

### 转换步骤

`llmexport` 工具支持将 HuggingFace/ModelScope 模型导出为 MNN 格式：

```bash
cd transformers/llm/export

# 1. 下载原始模型（以 Qwen3-0.6B-Instruct 为例）
# 从 https://modelscope.cn/qwen/Qwen3-0.6B-Instruct 下载

# 2. 导出为 MNN 格式
python llmexport.py \
    --path /path/to/Qwen3-0.6B-Instruct \
    --export mnn \
    --quant_bit 4          # 4-bit 量化，可选 4 或 8

# 3. 产物在 ./model 目录
```

### 关键参数

| 参数 | 说明 | 取值 |
|---|---|---|
| `--path` | 原始模型路径 | 本地路径或 HF/ModelScope ID |
| `--export` | 导出格式 | `mnn`、`onnx` |
| `--quant_bit` | 权重量化位宽 | `4`（推荐移动端）、`8` |
| `--lm_quant_bit` | lm_head 量化位宽 | `4`、`8` |
| `--weight_quant_bit` | 权重量化位宽（同上） | `4`、`8` |

### 量化级别选择建议

| 量化 | 模型体积（0.6B） | 内存占用 | 推理速度 | 质量损失 |
|---|---|---|---|---|
| Q4 | ~600MB | ~0.6GB | 最快 | 轻微 |
| Q8 | ~1.1GB | ~1.1GB | 中等 | 极小 |
| FP16 | ~2.2GB | ~2.5GB | 慢 | 无 |

**移动端推荐 Q4**：体积小、速度快、质量损失可接受。

### 验证转换结果

转换后可用 MNN 的 CLI demo 验证：

```bash
cd MNN/build
./llm_demo /path/to/model/config.json "你好"
```

如果输出正常中文回复，说明转换成功，可推送到设备使用。

## config.json 说明

`config.json` 是运行时配置，可在转换后手动调整关键字段：

```json
{
  "backend_type": "cpu",
  "thread_num": 4,
  "precision": "low",
  "memory": "low",
  "mllm": false,
  "llm_config": "llm_config.json",
  "llm_model": "llm.mnn",
  "llm_weight": "llm.mnn.weight",
  "embedding_model": "embeddings_bf16.bin",
  "tokenizer_file": "tokenizer.txt",
  "backend_config": {
    "backend_type": "opencl",
    "power": "normal",
    "memory": "normal",
    "precision": "normal"
  }
}
```

- `backend_type`：`cpu` 或 `opencl`（Android GPU）/ `metal`（iOS）
- `thread_num`：CPU 推理线程数
- `precision`：`low`（fp16）/ `high`（fp32）

## 常见问题

**Q: 转换时 OOM？**
A: 0.6B-1.8B 模型转换需 4-8GB 显存；7B 需 16GB+。可减小 batch 或用 CPU 转换（较慢）。

**Q: iOS 上内存超限被杀？**
A: 用 Q4 量化，并在 config.json 设置 `"memory": "low"`。MNN 会用 mmap 加载减少 dirty memory。

**Q: 推理速度比官方慢？**
A: 确认 `backend_type` 为 `opencl`（Android）/ `metal`（iOS）而非 `cpu`；检查 `thread_num` 是否匹配设备核心数。
