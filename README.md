# IRCC Tracker Safe (Windows) — v2.4.1 合并 · 双域名版（TLS 热修复）

一个**只在本机运行**的 Windows 小工具，用于查询你**自己**的 IRCC Application Status Tracker（申请状态）数据。

> 非官方工具，与 IRCC / Canada.ca / AWS 无任何隶属关系。仅用于查询你本人的账户。遇到 403、WAF 拦截或限流时请勿尝试绕过。

## 它是怎么工作的

1. 用你的 UCI + 密码，向 IRCC 使用的 **AWS Cognito** 登录，拿到 IdToken；
2. 在**本地**校验这枚 JWT（token_use / audience / issuer / 过期时间），任何一项不对都会中止；
3. 调用 IRCC Tracker API 的两个方法：
   - `get-profile-summary`（预检，仅供参考，**永不阻断**）；
   - `get-application-details`（权威结果，**总是执行**）；
4. 把结果分两段显示在**当前窗口**：Precheck（预检）+ Application details（申请详情）。

**隐私**：密码、Token、查询结果**只存在于内存**，程序退出即消失，**不写入任何文件或缓存**。始终开启 TLS 证书验证，**从不关闭**校验，也不向任何第三方发送数据。

## v2.4 相比 v2.3 的改动

1. **Cognito 登录错误精细化**（隐私安全）：解析 Cognito 返回的错误类型（含 `x-amzn-errortype` 响应头），把常见情况翻译成可操作的提示——例如「被风控拦截（不代表密码错）」「需要重置密码」「账号未激活」「尝试次数过多，等 15 分钟」。对不存在的 UCI 统一回「UCI 或密码不正确」，**不泄露某个 UCI 是否存在**。错误信息**永远不含**密码或 Token。
2. **申请详情解析更抗改版**：对 IRCC 可能变化的字段名做了多名称兜底（如 `relations`/`applications`/`apps`/`data`、`app`/`application`/`summary` 等）。
3. **确定性补全证书链**：IRCC 的 API 服务器返回的证书链缺少中间证书（`Entrust OV TLS Issuing RSA CA 2`），部分环境下会报「The SSL connection could not be established」。本版把这张**公开的**中间证书内置，并在校验时补齐——**仅**作用于 IRCC 的两个 API 域名，且证书仍必须链到系统信任的根，**没有降低任何安全性**。
4. **双域名自动 fallback**：把 API 域名与其对应的 `Origin`/`Referer` **成对**切换，先试 A、失败自动试 B，并在诊断里标明用的是哪一套。修正了旧版「API 用一个域名、Origin 用另一个」的不一致问题。

### 两套域名（成对切换，绝不混用）

| Endpoint | API | Origin / Referer | 对应站点 |
|---|---|---|---|
| **A**（默认先试）| `api.tracker-suivi.apps.cic.gc.ca` | `https://tracker-suivi.apps.cic.gc.ca` | 入籍(citizenship) tracker |
| **B**（A 失败时自动试）| `api.ircc-tracker-suivi.apps.cic.gc.ca` | `https://ircc-tracker-suivi.apps.cic.gc.ca` | 移民 application status tracker |

> 如果你查的是移民/PR 类申请、想默认先试 B，把脚本顶部 `$Endpoints` 数组里 A、B 两项的顺序对调即可（两套反正都会试）。

## 使用方法

1. 解压本压缩包，**保持 `.cmd` 和 `.ps1` 在同一个文件夹**里。
2. 双击 **`点击运行IRCC查询.cmd`**（它会自动设置 UTF-8，并优先用 PowerShell 7、否则用系统自带的 Windows PowerShell）。
3. 依次输入：
   - **UCI**：8 或 10 位数字，可带连字符（会自动去掉）；
   - **Application Number**：申请号；
   - **Tracker 密码**：输入时**不会显示**任何字符，这是正常的安全行为，输完按回车。
4. 查询结果显示在窗口里；失败时会给出**脱敏诊断**（不含密码/Token/响应体）。

## 常见结果说明

- **HTTP 500 / 502 / 503**：IRCC 服务端故障，客户端无法修复，过段时间再试。
- **HTTP 403**：被 IRCC 边缘/WAF 拦截。尽量用加拿大本地网络、关掉 VPN/代理；脚本化客户端仍可能被拦。
- **SSL connection could not be established**：证书链问题——本版已内置中间证书自动补链，通常不再出现。
- **登录被「security reasons」拦截**：Cognito 风控，**不代表密码错**，停止重试、稍后用官网。

## 安全须知

- 不接受用命令行参数传密码（避免进入命令历史）。
- 不保存密码、Token 或结果。
- 分享任何截图/报错前，请先遮盖 UCI、申请号、姓名、生日、地址等个人信息；**不要**把原始输出发到 GitHub Issue 或任何公开位置。
- 请手动、低频查询，不要高频轮询。

## License

MIT，见 [LICENSE](LICENSE)。


## v2.4.1 热修复（重要）

v2.4 引入的“自定义证书校验回调（ServerCertificateCustomValidationCallback）”在 PowerShell 中会在**没有 runspace 的工作线程**上执行并抛出异常，导致**所有** TLS 连接（包括最初的 AWS Cognito 登录）直接失败，报 `The SSL connection could not be established`。因此 v2.4 会卡在登录这一步，连查询都到不了。

v2.4.1 已移除该回调，改为在程序启动时把内置的 Entrust 中间证书导入到「当前用户 · 中间证书颁发机构（`CurrentUser\CA`）」存储、退出时自动移除，让**系统原生校验**自行补全证书链：

- **不降低安全性**：叶证书仍必须链接到系统信任的**根**证书；中间证书存储不是信任锚。
- **无需管理员权限**，退出时会把加进去的那张中间证书移除，保持你的证书存储原样。
- Cognito 登录恢复正常，双域名 A→B 自动 fallback 照常工作。

> 如果所在环境禁止写入 `CurrentUser\CA`（极少数受控设备），程序不会报错：主域名（endpoint A）用系统原生校验依然可用，仅备用的 ircc 域名（endpoint B）可能仍握手失败。
