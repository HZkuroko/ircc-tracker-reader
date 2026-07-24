# IRCC Tracker Safe Windows

请去右手边release下双版本呢的，这个是改了接口，而且有两种查询方式的

一个非官方、开源、隐私优先的 Windows IRCC Application Status Tracker 查询与诊断工具。

> [!IMPORTANT]
> **当前版本：v2.2（实验性 / 诊断用途）**
>
> 实测结论：AWS Cognito 登录**可以成功**，但 IRCC 数据接口（`get-profile-summary` / `get-application-details`）目前可能返回**空列表**或 **HTTP 500 Internal Server Error**；官方网页端本身也长期显示 “We’re experiencing a technical difficulty”。
>
> 这说明问题出在 **IRCC 服务端**，而不是本工具、你的账号或网络。本工具**不能保证**取得申请状态，也**无法修复** IRCC 服务端故障。

## 两个版本（本仓库提供两种）

本工具提供两个功能相同、只在“查询流程”上不同的版本，请按需选择：

| 版本 | 目录 | 查询流程 | 适用场景 |
|---|---|---|---|
| **Summary 预检版（本目录 · 推荐）** | `...-v2.2-summary` | 登录 → `get-profile-summary` 确认申请号属于当前账号 → `get-application-details` | 正常情况下的推荐版本，能提前拦截“申请号不属于该账号 / 账号下无申请”的问题 |
| **跳过 Summary 版** | `...-v2.2-skip-summary` | 登录 → **直接** `get-application-details`（跳过账号申请列表预检） | 当 `get-profile-summary` 返回空 / 报错、但你想测试详情接口是否仍能单独返回结果时使用；行为与早期 `.bat` 一致 |

> 说明：如果两个版本都失败（尤其是 `get-application-details` 返回 **HTTP 500**），基本可判定为 IRCC 服务端针对该账号 / 申请的故障，换任何版本或工具都无法绕过。

## 文件

```text
README.md                  GitHub 项目说明
使用教程.txt               普通用户使用说明
IRCC_Status_Check.ps1      主程序
点击运行IRCC查询.cmd       实际双击运行文件
LICENSE                    MIT License
.gitignore                 防止误上传敏感运行文件
```

## v2.2 更新

- 提供 **Summary 预检版** 与 **跳过 Summary 版** 两个并行版本，覆盖不同的接口故障场景；
- 补充实测诊断结论：登录成功但数据接口可能返回空或 HTTP 500，属 **IRCC 服务端问题**；
- 修正 README 中 IRCC 查询端点笔误（正确为 `https://api.tracker-suivi.apps.cic.gc.ca/user`）；
- 版本号与窗口标题统一更新为 v2.2；
- 其余安全、隐私与诊断行为与 v2.0 保持一致。

## v2.0 改进

- 优先使用 PowerShell 7；未安装时回退至 Windows PowerShell 5.1；
- 网络层改用 `System.Net.Http.HttpClient`；
- 增加合理的 `Accept`、`Origin`、`Referer`、User-Agent 和 no-cache Header；
- Cognito 登录后在本地检查 JWT 的 `token_use`、`aud`、`iss` 和过期时间；
- 先调用 `get-profile-summary`，精确确认 Application Number 属于当前账号；
- 再调用 `get-application-details`，避免盲目读取第一条记录；
- 默认不创建 `StatusCheck.txt`，结果只显示在当前窗口；
- 不自动重试；失败后由用户选择退出或**手动重试一次**；
- 最多两次总尝试（首次 + 一次手动重试）；
- 保留脱敏诊断信息，但不显示响应正文、Token、凭据或申请编号；
- UCI 可输入纯数字或官方带连字符格式，内部统一转换为 8 位/10 位纯数字；
- 输入 UCI 和 Application Number 后自动清屏。

## 工作流程（Summary 预检版）

```text
用户输入 UCI、Application Number、密码
                    ↓
AWS Cognito 登录并取得临时 IdToken
                    ↓
本地验证 JWT 的用途、受众、签发者和有效期
                    ↓
get-profile-summary 精确匹配 Application Number
                    ↓
get-application-details 读取申请状态
                    ↓
只在当前窗口显示；退出后不保存结果
```

## 使用方法

1. 下载并完整解压项目，不要直接在 ZIP 中运行；
2. 放到本机非共享、非 OneDrive/Dropbox 同步目录；
3. 双击 `点击运行IRCC查询.cmd`；
4. 输入：
   - UCI（只输入一次；支持 `12345678`、`1234-5678`、`1234567890` 或 `12-3456-7890`）；
   - Application Number；
   - Tracker 密码；
5. 密码不会显示；完成输入后终端自动清屏；
6. 等待登录、账号申请列表和申请详情三个阶段完成。

如果失败，程序会显示脱敏诊断，并提供：

```text
R：手动重试一次
Q：立即退出
```

程序不会自动重试。第二次失败后不再提供重试。

## 诊断信息

当前诊断版可能显示：

- 出错阶段；
- 固定端点的主机和路径；
- PowerShell 版本；
- HTTP 传输实现；
- TLS 协议；
- HTTP 状态码（如果服务器有返回）；
- Content-Type；
- 响应字符数；
- 请求耗时；
- 异常类型和不含秘密信息的异常消息；
- JWT 检查是否通过。

诊断信息不会显示：

- 密码；
- UCI 或 Application Number；
- IdToken、AccessToken、RefreshToken、Session；
- Authorization Header；
- 请求体或响应正文；
- 完整申请数据。

提交错误截图时，只保留红色错误和诊断区域，确认没有输入画面或个人资料。

## 网络与隐私

本工具只访问：

| 用途 | 地址 |
|---|---|
| Cognito 登录 | `https://cognito-idp.ca-central-1.amazonaws.com/` |
| IRCC 查询 | `https://api.tracker-suivi.apps.cic.gc.ca/user` |

它不会：

- 把凭据写入脚本或日志；
- 把 Token 写入磁盘；
- 保存查询结果或历史；
- 使用第三方服务器、Webhook、广告或遥测；
- 下载或执行远程代码；
- 关闭 TLS 证书验证；
- 自动轮询或高频重试；
- 修改 IRCC 申请资料。

PowerShell 进程在登录时仍必须短暂持有明文密码。不要在公共电脑、受感染电脑或不受信任设备上运行。

## 请求兼容性

IRCC API 请求会附带：

```text
Accept: application/json
Content-Type: application/json
Origin: https://ircc-tracker-suivi.apps.cic.gc.ca
Referer: https://ircc-tracker-suivi.apps.cic.gc.ca/
User-Agent: browser-compatible value
Cache-Control: no-store
Pragma: no-cache
Authorization: Bearer <temporary token>
```

这些 Header 用于提高与 IRCC 网关的正常兼容性，不用于绕过身份验证或访问控制。

## 常见错误

| 错误 | 说明 |
|---|---|
| Cognito HTTP 401/403 | 登录信息、Client ID 或认证流程被拒绝 |
| Unsupported challenge | 账号要求 MFA、密码重置或其他步骤；脚本不会绕过 |
| JWT validation failed | Token 用途、受众、签发者或有效期与预期不符 |
| Profile summary 无申请 | 当前账号没有返回可查询申请（可能是账号 / 申请未关联，或 IRCC 服务端故障）|
| Application Number 不匹配 | 输入编号不在当前认证账号的 summary 中 |
| IRCC HTTP 429 | 请求过多；停止运行并等待 |
| IRCC HTTP 500/502/503 | IRCC 服务端或网关不可用（已确认为当前主要故障类型）|
| `underlying connection was closed` | 服务器/网关或旧网络栈在 HTTP 响应前关闭连接 |
| 非 JSON | 可能返回维护页面 |
| JSON 格式变化 | IRCC 修改了响应结构 |

## Security 字段

如果返回内容包含 `key="Security"`，程序只显示：

> 检测到 Security 历史节点（不等同于确认进入深度安调）。

该字段不能单独证明已进入深度安调、仍在进行或节点日期就是实际开始日期。

## PowerShell 7

启动器会自动检查 `pwsh.exe`：

- 已安装：优先使用 PowerShell 7 的现代 HTTP 运行环境；
- 未安装：使用系统自带 Windows PowerShell 5.1。

程序不会自动下载或安装 PowerShell 7。

## 安全规则

- 只查询本人或获授权管理的申请；
- 不要高频重复运行；
- 不要分享凭据、Token、UCI、Application Number 或响应正文；
- 不要关闭证书验证；
- 不要把请求转发给陌生代理或第三方服务器；
- 不要通过脚本尝试绕过 MFA、验证码、访问限制或限流。

## 已知限制

- 依赖 IRCC 未公开承诺长期稳定的网页后端接口；
- Client ID、User Pool、请求 Header、API 和 JSON 结构都可能改变；
- `get-profile-summary` 与详情请求使用相同 API 主机，主机不可用时两个阶段都会失败；
- 请求头和 HttpClient 只能提高兼容性，不能修复服务端中断；
- 当前版本仍未在可稳定返回数据的 IRCC 环境中完成端到端验证。

## GitHub 发布

建议 Release：

```text
Tag: v2.2-diagnostic
Title: v2.2 Diagnostic — dual edition (summary / skip-summary)
Pre-release: 是
```

README 顶部必须保留实验性和当前接口不稳定的提示。发布前确认仓库中没有任何真实凭据、截图、Token、日志或查询结果。

## License

[MIT License](LICENSE)

---

> 非官方项目；与 IRCC、Canada.ca 或 AWS 无任何隶属关系。
