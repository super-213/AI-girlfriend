import os
from openai import OpenAI

client = OpenAI(
    api_key="sk-1ac0811715e94f11bb38c24f0e1db359",
    base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
)

# 开启流式输出
stream = client.chat.completions.create(
    model="qwen-plus",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "你是谁？"},
    ],
    stream=True,  # <<< 关键：开启流式
)

# 手动打印每一块数据（模拟 Swift 收到的原始 data）
for chunk in stream:
    print(chunk.model_dump_json())  # 每个 chunk 是一个部分响应