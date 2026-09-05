# Security Policy

## Supported versions

PromptPick 目前处于 Pre-release 阶段，仅维护最新 GitHub Release 和 `main` 分支。

## Reporting a vulnerability

请不要为安全漏洞创建公开 Issue。使用 GitHub 仓库的 **Security → Report a vulnerability** 私下提交报告；如果该入口不可用，请通过仓库所有者公开资料中的联系方式联系维护者。

报告请包含影响范围、复现步骤和建议修复方式，但不要附带真实密码、Token、公司机密或其他人的剪贴板数据。

## Sensitive data boundary

PromptPick 会读取系统剪贴板，因此任何新增的网络访问、遥测、崩溃上报或同步能力都必须默认关闭，并在合并前完成明确的隐私审查。
