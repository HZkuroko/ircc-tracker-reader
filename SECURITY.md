# Security Policy

## Supported version

仅维护仓库中的最新版本。旧压缩包、聊天附件、第三方网盘副本和 fork 不受支持。

## Reporting a vulnerability

请优先使用 GitHub **Private vulnerability reporting / Security Advisory**，不要公开提交包含利用细节或用户数据的 Issue。

报告中可以包含：

- 受影响版本和文件；
- 不含秘密信息的复现步骤；
- 预期与实际行为；
- 建议修复方案。

严禁包含：

- Tracker 用户名或密码；
- Token、Session 或 Authorization header；
- UCI、Application Number、document number；
- 未打码截图、完整请求/响应或日志。

## Security invariants

维护者不应接受以下变更：

- 把密码或 Token 写入磁盘；
- 新增未知第三方网络地址或遥测；
- 关闭 TLS 证书验证；
- 使用 `iex` / `Invoke-Expression` 执行网络内容；
- 自动绕过 MFA、验证码或其他认证挑战；
- 高频轮询、隐藏重试或规避限流；
- 把内部 `Security` 字段描述为确定的深度安调结论。

## Compromised credentials

如果凭据曾被写入脚本、提交到 Git、发送到群聊或上传到云盘，应删除相关文件和历史，并立即更改对应密码。仅删除最新一次 commit 不足以从 Git 历史中移除秘密。
