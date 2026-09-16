# Voice Book 📚🎧

[![GitHub](https://img.shields.io/badge/GitHub-zhdgzs%2Fvoice--book-blue?logo=github)](https://github.com/zhdgzs/voice-book)
[![Gitee](https://img.shields.io/badge/Gitee-zhdgzs%2Fvoice--book-red?logo=gitee)](https://gitee.com/zhdgzs/voice-book)

一款专注于隐私保护的离线本地有声书播放器，采用 Flutter 开发，~~支持跨平台使用~~ 没有mac，不能调试，目前只支持安卓。

如有问题，请在Github仓库反馈；已发布的apk，也在Github的Release页

**此项目就是一个作者个人使用的离线、无广告、轻量级的听书APP，个人感觉功能已完善，暂时不会更新版本，如有新需求，可以提issues**

## ✨ 特性

- 🔒 **完全离线** - 所有数据存储在本地，不联网，保护隐私
- ☁️ **WebDAV 网盘导入** - 支持配置 WebDAV 书源，浏览网盘目录，下载音频导入书架
- 🎵 **多格式支持** - 支持 MP3、M4A等常见音频格式
- 📖 **智能管理** - 自动扫描和组织有声书文件
- ⏱️ **进度记忆** - 自动保存播放进度，随时继续收听
- 🔖 **书签功能** - 标记重要片段，快速跳转
- ⏰ **睡眠定时** - 设置定时停止播放
- 🎨 **简洁界面** - 清爽的 Material Design 设计
- ⚡ **低资源占用** - 优化性能，流畅运行

## 📱 支持平台

- ✅ Android
- ⏳ iOS ~~(计划中)~~ 暂时没计划

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0

### 安装步骤

1. 克隆仓库
```bash
git clone https://github.com/yourusername/voiceBook.git
cd voiceBook
```

2. 安装依赖
```bash
flutter pub get
```

3. 运行应用
```bash
flutter run
```

## 🛠️ 技术栈

- **框架**: Flutter
- **状态管理**: Provider
- **本地存储**: SQLite (sqflite)
- **音频播放**: just_audio
- **权限管理**: permission_handler

## 📂 项目结构

```
lib/
├── models/             # 数据模型
├── providers/          # 状态管理
├── screens/            # 页面
├── widgets/            # 组件
├── services/           # 服务层
├── utils/              # 工具类
└── main.dart           # 应用入口
```

## 🗺️ 开发路线图

### MVP 版本 (v0.1.0)
- [x] 项目初始化
- [x] 基础架构搭建
- [x] 主题切换
- [x] 音频文件管理
- [x] 音频播放功能
- [x] 播放进度记忆
- [x] 书籍管理

### 增强版本 (v0.2.0)
- [x] 书签功能
- [x] 跳过开头结尾
- [x] 睡眠定时器

### 正式版本 (v1.0.0)
- [ ] 常驻通知栏
- [ ] 性能优化

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源协议。

## 📧 联系方式

如有问题或建议，欢迎通过 Issue 反馈，请在Github仓库反馈。
