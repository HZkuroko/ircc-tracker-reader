# IRCC Tracker Safe Windows

一个非官方、开源的 Windows 查询脚本，用于在 IRCC Application Status Tracker 网页不可用时，尝试查询**你本人或你获授权管理的申请**。

> [!IMPORTANT]
> **当前状态：实验性。** 2026-07-24 实测中，AWS Cognito 登录可以成功，但 IRCC 数据接口可能在返回结果前主动关闭连接。因此，目前不能保证取得申请状态。本项目与 IRCC、加拿大政府或 AWS 没有隶属或授权关系。

## 文件说明

仓库刻意保持精简：

```text
README.md                  说明、教程、安全与排错（本文件）
IRCC_Status_Check.ps1      主程序
点击运行IRCC查询.cmd           Windows 双击启动器
LICENSE                    MIT 开源许可
.gitignore                 防止误上传日志和本地敏感文件
```

真正运行时只需要 `.ps1` 和 `.cmd`；其余三个文件用于 GitHub 项目说明、授权和隐私保护。

## 工作原理

```text
用户输入账号和密码
        ↓
AWS Cognito 登录并返回临时 Token
        ↓
脚本携带 Token、Application Number 和 UCI
请求 IRCC Tracker 数据接口
        ↓
整理状态并写入本地 StatusCheck.txt
```

这不是绕过登录：必须使用用户自己的有效凭据。脚本不会提交或修改申请。

## 安全与隐私

脚本只连接以下两个固定 HTTPS 地址：

| 用途 | 地址 | 发送的数据 |
|---|---|---|
| 登录 | `https://cognito-idp.ca-central-1.amazonaws.com/` | Tracker 用户名、密码、公开 Client ID |
| 查询 | `https://api.ircc-tracker-suivi.apps.cic.gc.ca/user` | 临时 Token、Application Number、UCI、`isAgent=false` |

安全设计：

- 密码在运行时隐藏输入，不写入脚本或日志；
- 输入完成后自动清屏，减少截图泄露风险；
- Token 不写入磁盘；
- 没有遥测、广告、Webhook 或第三方数据上传；
- 不使用 `iex` / `Invoke-Expression`；
- 不下载或执行远程代码；
- 不关闭 TLS 证书验证；
- 日志最多保留最近 30 次，并尝试限制为当前 Windows 用户访问。

`StatusCheck.txt` 虽然不记录密码、Token、UCI 或申请号，但申请状态仍属于个人隐私。不要上传到 GitHub、网盘、群聊或 Issue。

## 系统要求

- Windows 10 或 Windows 11；
- Windows PowerShell 5.1；
- 用户本人的 IRCC Tracker 凭据；
- 可访问 AWS Cognito 和 IRCC Tracker API 的网络。

## 使用教程

1. 下载仓库 ZIP 或从 Releases 下载压缩包；
2. **完整解压**，不要直接在 ZIP 中运行；
3. 放在本机非共享、非 OneDrive/Dropbox 同步目录；
4. 双击 `点击运行IRCC查询.cmd`；
5. 依次输入：
   - Tracker 用户名（通常为 UCI）；
   - Application Number；
   - UCI；
   - Tracker 密码；
6. 密码输入时不会显示文字或星号，输入完按 Enter；
7. 成功时，窗口显示状态，并在同目录生成 `StatusCheck.txt`。

> [!WARNING]
> 不要把密码写进 `.ps1`、`.cmd`、配置文件、Issue 或截图。不要在公共电脑或公司受管电脑上绕过安全策略运行。

### Windows 阻止执行时

1. 不要关闭 Windows Defender；
2. 先用记事本打开 `.ps1` 检查代码；
3. 右键下载的 ZIP 或脚本 → **属性**；
4. 如果有“解除锁定 / Unblock”，确认来源可信后勾选并应用；
5. 重新解压再运行。

启动器使用进程级 `ExecutionPolicy Bypass`，只运行同目录中明确命名的 `IRCC_Status_Check.ps1`。它不使用 `iex`，也不会下载代码。

## 查询结果

可能显示：

- 系统最后更新日期；
- Eligibility；
- Medical；
- Biometrics；
- Background；
- Security 历史节点及日期。

### Security 字段说明

检测到 `key="Security"` 最多只能说明响应中存在一个名为 Security 的历史节点，**不能单独证明**：

- 已进入深度安调；
- 安调仍在进行；
- 节点日期就是实际安调开始日期。

应以 IRCC 正式通知、GCMS 记录或其他官方信息为准。

## 常见错误

| 错误 | 说明 |
|---|---|
| HTTP 401 | 登录或 Token 被拒绝 |
| HTTP 403 | 权限或接口规则拒绝请求 |
| HTTP 429 | 请求过于频繁，应停止并等待 |
| HTTP 500/502/503 | IRCC 服务端或网关不可用 |
| `underlying connection was closed` | 数据接口或网关在返回 HTTP 响应前关闭连接 |
| `non-JSON response` | 返回了维护页面或其他非 JSON 内容 |
| `response format may have changed` | IRCC 修改了响应结构，当前版本需要更新 |
| 无法匹配申请记录 | 返回多条记录，但无法安全确认目标申请 |

排错时只分享红色错误行。不得分享：

- Tracker 用户名或密码；
- UCI、Application Number、document number；
- Token、Session、Authorization header；
- 请求/响应正文；
- 未打码截图或 `StatusCheck.txt`。

如果登录成功后出现 `underlying connection was closed`，而开关 VPN 和原版脚本结果相同，通常表示 IRCC 数据接口或中间网关不可用。此时应停止反复尝试，不要添加高频重试。

## 删除数据

- 删除查询历史：关闭程序后删除 `StatusCheck.txt`；
- 停止使用：删除整个项目文件夹；
- 如果曾把真实密码写进旧版脚本，应删除旧文件、回收站副本及云端历史；
- 如果凭据曾上传到 GitHub、网盘或群聊，应立即修改密码。仅删除最新 commit 不能清除 Git 历史中的秘密。

## 贡献与安全规则

提交 Issue 或 Pull Request 时：

- 不得使用真实凭据或申请数据；
- 不得新增未知网络端点、遥测或 Webhook；
- 不得关闭 TLS 证书验证；
- 不得执行下载的代码；
- 不得绕过 MFA、验证码、访问控制或限流；
- 新增网络地址必须在 README 中披露；
- 缺失字段必须显示“未能读取”，不能伪装为成功；
- 不得把 `Security` 节点宣传为确定进入深度安调。

发现安全问题时，请使用 GitHub Private Vulnerability Reporting，不要公开提交包含秘密信息的 Issue。

## 已知限制

- 依赖未承诺长期稳定的网页后端接口；
- IRCC 可随时调整 Client ID、认证流程、API 或响应结构；
- PowerShell 进程在登录时仍必须短暂持有明文密码；
- 频繁查询可能触发限流；
- 当前数据接口可能主动关闭连接，不能保证端到端可用；
- 项目不提供移民或法律建议。

## 发布到 GitHub

建议仓库名：

```text
ircc-tracker-safe-windows
```

首个 Release 建议：

```text
Tag: v1.4.0
Title: v1.4.0 — Initial public release
```

发布前务必确认上传列表中没有：

```text
StatusCheck.txt
*.log
.env
真实凭据、Token、UCI、申请号或运行截图
```

建议开启 GitHub **Private vulnerability reporting**，并在 Release 中保留“当前 IRCC 数据接口可能不可用”的说明。

## License

本项目使用 [MIT License](LICENSE)。
