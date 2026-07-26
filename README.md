# IRCC Tracker Safe Windows

一个非官方、开源、隐私优先的 Windows IRCC Application Status Tracker 查询与诊断工具。

> [!IMPORTANT]
> **当前版本：v2.3（实验性 / 诊断用途 · 单一合并版）**
>
> 实测结论：AWS Cognito 登录**可以成功**，但 IRCC 数据接口（`get-profile-summary` / `get-application-details`）目前可能返回**空列表**或 **HTTP 500 Internal Server Error**；官方网页端本身也长期显示 “We're experiencing a technical difficulty”。
>
> 这说明问题多出在 **IRCC 服务端**，而不是本工具、你的账号或网络。本工具**不能保证**取得申请状态，也**无法修复** IRCC 服务端故障。

> [!NOTE]
> **v2.3 起脚本界面全部英文**（`.ps1` 为纯 ASCII），从根本上避免在非中文 Windows 上出现中文乱码 / 脚本解析错误。中文 `使用教程.txt` 保留，仅供阅读，不参与程序运行。

## 单一合并版（不再区分双版本）

v2.3 把旧的 “Summary 预检版” 和 “跳过 Summary 版” 合并为**一个版本**，采用优雅降级：

1. **登录** → AWS Cognito 取得临时 IdToken → 本地校验 JWT；
2. **Profile summary 预检（仅信息，不阻断）**：读取账号申请列表，判断申请号是否属于当前账号。即使返回**空 / 不匹配 / 报错**，也**不会中止**后续查询；
3. **Application details（权威结果，始终执行）**：无论预检结果如何，都直接查询申请详情；
4. **分区列出两段结果**：预检小结 + 申请详情。整体成败只看 **details** 这一步。

> 好处：一个版本涵盖所有场景，无需选择；且 “summary 是否可用” 本身成为可见的诊断线索。

## 文件

```text
README.md                  项目说明
使用教程.txt               中文使用指南（不影响程序）
IRCC_Status_Check.ps1      主程序（合并版）
点击运行IRCC查询.cmd       双击运行入口（英文内容 + chcp 65001）
LICENSE                    MIT License
.gitignore                 防止误上传敏感运行文件
```

## v2.3 更新

- **合并为单一版本**：summary 预检降级为非阻断的信息步骤，无论空 / 不匹配 / 报错都继续查询 details，并同时列出两段结果与两段诊断；
- **脚本全面英文化**：`.ps1` 内所有交互文案改为英文，文件为纯 ASCII，修复非中文系统的编码乱码 / 解析报错；
- **浏览器兼容头**：IRCC API 请求补充 `Sec-Fetch-Site/Mode/Dest`、`sec-ch-ua` 等浏览器一致请求头（仅用于兼容，不绕过任何鉴权或访问控制）；
- **HTTP 错误分场景诊断**：401/403/429/5xx 会根据阶段（Cognito 登录 vs IRCC 接口）给出更明确提示；
- **修复**：`Select-RelationForUci` 误用 PowerShell 自动变量 `$matches`，已重命名。

## 工作流程

```text
用户输入 UCI、Application Number、密码
                    |
AWS Cognito 登录并取得临时 IdToken
                    |
本地验证 JWT 的用途、受众、签发者和有效期
                    |
get-profile-summary 预检（信息，不阻断）
                    |
get-application-details 读取申请状态（权威）
                    |
分区显示 预检小结 + 申请详情；退出后不保存结果
```

## 使用方法

1. 下载并**完整解压**项目，不要直接在 ZIP 中运行；
2. 放到本机非共享、非 OneDrive/Dropbox 同步目录；
3. 双击 `点击运行IRCC查询.cmd`；
4. 依次输入 **UCI**（支持 `12345678`、`1234-5678`、`1234567890` 或 `12-3456-7890`）、**Application Number**、**Tracker 密码**（不显示）；
5. 完成输入后终端自动清屏，等待登录、预检、详情三个阶段完成。

失败时显示脱敏诊断，并提供：

```text
R：手动重试一次
Q：立即退出
```

程序不会自动重试；第二次失败后不再提供重试。

## 诊断信息

可能显示：出错阶段、固定端点主机与路径、PowerShell 版本、HTTP 传输实现、TLS 协议、HTTP 状态码、Content-Type、响应字符数、请求耗时、异常类型与不含秘密的异常消息、JWT 检查结果，以及针对 HTTP 错误的 `Hint`。合并版在 details 失败时会分别打印 **profile summary** 与 **application details** 两段诊断。

**不会**显示：密码、UCI / Application Number、任何 Token / Session、Authorization Header、请求体或响应正文、完整申请数据。

> 提交错误截图时，只保留红色错误和诊断区域，确认没有输入画面或个人资料。

## 网络与隐私

本工具只访问：

| 用途 | 地址 |
|---|---|
| Cognito 登录 | `https://cognito-idp.ca-central-1.amazonaws.com/` |
| IRCC 查询 | `https://api.tracker-suivi.apps.cic.gc.ca/user` |

它不会：写凭据 / Token 到磁盘、保存查询结果或历史、使用第三方服务器 / Webhook / 遥测、下载或执行远程代码、关闭 TLS 证书验证、自动轮询或高频重试、修改 IRCC 申请资料。

> PowerShell 进程在登录时仍必须短暂持有明文密码。不要在公共电脑、受感染电脑或不受信任设备上运行。

## 常见错误

| 错误 | 说明 |
|---|---|
| Cognito HTTP 401/403 | 登录信息、Client ID 或认证流程被拒绝（可能触发风控）|
| `NotAuthorizedException / security reasons` | Cognito 自适应认证（风控）拦截；换本地网络、关 VPN 后再试，脚本无法绕过 |
| Unsupported challenge | 账号要求 MFA / 改密码等；脚本不会绕过 |
| JWT validation failed | Token 用途、受众、签发者或有效期不符 |
| Profile summary 无申请 | 账号没有返回可查询申请（账号 / 申请未关联，或服务端故障）；合并版仍会继续查 details |
| Application Number 不匹配 | 输入编号不在当前认证账号的 summary 中；合并版仍会继续查 details |
| IRCC HTTP 403 | 接口 / 边缘（WAF/CDN）拦截；关 VPN、用加拿大本地网络再试 |
| IRCC HTTP 429 | 请求过多；停止并等待 |
| IRCC HTTP 500/502/503 | IRCC 服务端或网关不可用（当前主要故障类型）|
| 非 JSON / JSON 格式变化 | 返回维护页面，或 IRCC 修改了响应结构 |

## PowerShell 7

启动器自动检查 `pwsh.exe`：已安装则优先使用 PowerShell 7 的现代 HTTP 运行环境；未安装则回退到系统自带 Windows PowerShell 5.1。程序不会自动下载或安装 PowerShell 7。

## 安全规则

- 只查询本人或获授权管理的申请；
- 不要高频重复运行；
- 不要分享凭据、Token、UCI、Application Number 或响应正文；
- 不要关闭证书验证；不要把请求转发给陌生代理；
- 不要通过脚本尝试绕过 MFA、验证码、访问限制或限流。

## 已知限制

- 依赖 IRCC 未公开承诺长期稳定的网页后端接口；
- Client ID、User Pool、请求 Header、API 与 JSON 结构都可能改变；
- 预检与详情请求使用相同 API 主机，主机不可用时两个阶段都会失败；
- 请求头和 HttpClient 只能提高兼容性，**不能修复服务端中断**；
- 当前版本仍未在可稳定返回数据的 IRCC 环境中完成端到端验证。

## License

[MIT License](LICENSE)

---

> 非官方项目；与 IRCC、Canada.ca 或 AWS 无任何隶属关系。
