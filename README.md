# AI 看板娘

一个基于 SwiftUI 的 macOS AI 看板娘应用，支持 OpenAI API 格式的 API 调用。

## 项目结构

```
___/
├── Sources/              # 源代码目录
│   ├── App/             # 应用入口
│   ├── Views/           # 视图层
│   ├── ViewModels/      # 视图模型
│   ├── Models/          # 数据模型
│   ├── Services/        # 服务层（API等）
│   ├── UI/              # UI组件和设计系统
│   └── Utils/           # 工具类
├── Resources/           # 资源文件
│   ├── Assets.xcassets/ # 图标资源
│   └── Animations/      # GIF动画
├── Preview Content/     # 预览资源
├── ___.entitlements    # 应用权限配置
├── README.md
└── LICENSE
```

## 功能特性

- 透明悬浮窗口
- AI 对话交互
- 动态 GIF 动画
- 偏好设置面板
- 支持 OpenAI API 格式
