# PromptPick

**为 AI 重度用户设计的 Mac 剪贴板，能把好 Prompt 收藏起来并随时调用。**

PromptPick 把临时的剪贴板历史和长期的 Prompt 资产库放在同一个快捷面板里。复制到一条好 Prompt 后，可以立即收藏、命名和归类；下次打开 ChatGPT、Claude、Cursor 或其他 AI 工具时，按场景、关键词或最近使用快速找到并粘贴。

## 当前能力

- 剪贴板历史与搜索
- 从剪贴板历史收藏 Prompt
- Prompt 场景分类与最近使用
- 固定 Prompt 一键粘贴
- 变量 Prompt 引导填写、实时预览与粘贴
- Prompt JSON 备份与恢复
- 数据默认保存在本机

## 下载与安装

从 [Releases](https://github.com/zairuilab/PromptPick/releases) 下载最新 ZIP：

1. 解压 `PromptPick-*.zip`。
2. 把 `PromptPick.app` 拖入“应用程序”。
3. 首次启动时右键 PromptPick，选择“打开”，再次确认“打开”。
4. 如需自动粘贴，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 PromptPick。

当前为 Dogfood 预览版，采用临时签名且尚未经过 Apple 公证。受公司 MDM 管理的 Mac 可能禁止运行；正式公开 Beta 会改用 Developer ID 签名与 Apple 公证。

## 反馈

试用中遇到问题或有建议，请在 [Issues](https://github.com/zairuilab/PromptPick/issues) 提交。请勿在截图或描述里包含密码、Token、公司机密或其他敏感剪贴板内容。

## 隐私与源码

PromptPick 当前以闭源预览方式测试，公开仓库只用于版本下载、说明和反馈；完整产品源码保存在私有开发仓库。PromptPick 基于开源项目 Maccy 衍生开发，并持续保留其 MIT License 与第三方许可证义务。
