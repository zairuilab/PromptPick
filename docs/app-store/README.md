# PromptPick Mac App Store 发布包

这里是 Mac App Store 版本的单一事实源。商店包与直接下载的 Dogfood 包分开构建：商店版本使用 App Sandbox、Apple Distribution 签名，并通过 App Store Connect 交付；直接下载版本才保留独立更新与试用分发策略。

## 已验证

- Bundle ID：`com.zairuilab.promptpick`
- 版本：`0.2.0 (1)`
- 架构：`arm64 + x86_64`
- `com.apple.security.app-sandbox = true`
- 使用 Apple Distribution 证书与 Mac Team Store Provisioning Profile
- 不嵌入 Sparkle
- 已生成：`build/AppStore3/export/PromptPick.pkg`

## 重复构建

```bash
./scripts/package-app-store.sh
./scripts/validate-app-store-bundle.sh build/AppStoreRelease/PromptPick.xcarchive/Products/Applications/PromptPick.app
pkgutil --check-signature build/AppStoreRelease/export/PromptPick.pkg
```

## 当前提交前阻塞项

1. App Store Connect 产品记录已创建：PromptPick，App ID `6818366986`，Bundle ID `com.zairuilab.promptpick`。
2. 支持网址与隐私政策网址需放到真实可访问的 PromptPick 页面，不能用临时占位地址。
3. `0.2.0 (2)` 已上传并等待处理；App Store 截图、年龄分级和审核备注仍需在 Connect 中填写。
4. 上传后先做 TestFlight 内部测试，再提交审核。

## 商店文案初稿

- 名称：PromptPick
- 副标题：AI 剪贴板与 Prompt 库
- 类别：Productivity
- 一句话：为 AI 重度用户设计的 Mac 剪贴板，把复制过的好 Prompt 收藏起来并随时调用。
- 核心流程：复制 → 收藏 → 按场景或关键词找到 → 变量填写 → 粘贴到当前对话。
