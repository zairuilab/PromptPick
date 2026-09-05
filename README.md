# PromptPick

**为 AI 重度用户设计的 Mac 剪贴板：把复制过的好 Prompt 收藏起来，并在任何 AI 对话中快速找到、填写和调用。**

PromptPick combines clipboard history with a reusable Prompt library for macOS.

## 为什么做 PromptPick

普通剪贴板把所有复制内容按时间排列，但 Prompt 更像需要长期保存、分类和重复调用的资产。PromptPick 将两种内容放进同一个快捷面板：

- 临时内容继续留在剪贴板历史中；
- 好 Prompt 可以从历史记录直接收藏、命名和归类；
- 固定模板可以直接粘贴；
- 带变量的模板会先用自然语言表单引导填写，再生成最终 Prompt。

## 当前能力

- 剪贴板历史、搜索与来源应用展示
- 从剪贴板历史收藏为 Prompt
- Prompt 场景分类、关键词搜索和最近使用
- 固定 Prompt 一键粘贴
- 变量 Prompt 引导填写、实时预览和粘贴
- Prompt JSON 导入与导出
- 数据默认保存在本机
- 菜单栏常驻、全局快捷呼出和完整退出路径

## 下载

从 [GitHub Releases](https://github.com/zairuilab/PromptPick/releases) 下载最新 Dogfood 版本。

当前安装包使用临时签名，尚未经过 Apple 公证。首次运行可右键 App 选择“打开”；受公司 MDM 管理的 Mac 可能禁止运行。

## 开发环境

- macOS 14+
- Xcode 16+
- Swift / SwiftUI / AppKit

克隆仓库后，用 Xcode 打开 `Maccy.xcodeproj`，选择 `Maccy` Scheme 构建运行。Swift Package 版本锁定在 `Package.resolved`。

```bash
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -destination 'platform=macOS' \
  build
```

## 测试

项目包含单元测试和 macOS UI 测试。UI Runner 建议使用系统标准 DerivedData 目录；运行测试前请退出其他同 Bundle ID 的 PromptPick 实例。

```bash
xcodebuild build-for-testing \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -testPlan Maccy \
  -destination 'platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/PromptPick-UIRunner"

xcodebuild test-without-building \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -testPlan Maccy \
  -destination 'platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/PromptPick-UIRunner"
```

UI 自动化需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Xcode 及测试 Runner。

## 隐私

PromptPick 处理的剪贴板和 Prompt 数据默认只保存在本机。提交 Issue 时请勿上传包含密码、Token、公司机密或其他敏感剪贴板内容的截图和日志。

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

## 参与贡献

Bug、体验问题和功能建议可以通过 [Issues](https://github.com/zairuilab/PromptPick/issues) 提交。贡献代码前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 来源与许可证

PromptPick 基于 [Maccy](https://github.com/p0deje/Maccy) 衍生开发：

- Maccy 原始代码保留其 MIT License，见 [LICENSE](LICENSE)；
- PromptPick 新增与修改代码采用 MIT License，见 [LICENSE-PROMPTPICK](LICENSE-PROMPTPICK)；
- 派生版本和隔离边界见 [DERIVATION_NOTICE.md](DERIVATION_NOTICE.md)；
- 第三方依赖和许可证正文见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 `THIRD_PARTY_LICENSES/`；
- MIT License 不授予 PromptPick 名称与标识的商标使用权，见 [TRADEMARKS.md](TRADEMARKS.md)。

## 项目状态

PromptPick 仍处于 Dogfooding / Pre-release 阶段。当前重点是验证真实用户能否持续复用 Prompt 工作流，而不是快速堆叠功能。
