# IRCC Tracker Safe Windows v1.4.0
# SPDX-License-Identifier: MIT
# Unofficial project; not affiliated with IRCC, Canada.ca, or AWS.
# Credentials are requested at runtime and are never written to this file or the log.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$AuthUri = 'https://cognito-idp.ca-central-1.amazonaws.com/'
$ApiUri = 'https://api.ircc-tracker-suivi.apps.cic.gc.ca/user'
$ClientId = '3cfutv5ffd1i622g1tn6vton5r'
$LogPath = Join-Path $PSScriptRoot 'StatusCheck.txt'
$KeepHistory = $true
$MaxHistoryEntries = 30

# Require modern TLS on Windows PowerShell 5.1.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Read-RequiredText {
    param([string]$Prompt)
    do {
        $value = (Read-Host $Prompt).Trim()
    } while ([string]::IsNullOrWhiteSpace($value))
    return $value
}

function Invoke-JsonPost {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body,
        [string]$StepName
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri `
            -Method Post `
            -Headers $Headers `
            -Body $Body `
            -ContentType $Headers['Content-Type'] `
            -UseBasicParsing `
            -MaximumRedirection 0 `
            -TimeoutSec 30

        $contentType = [string]$response.Headers['Content-Type']
        # AWS Cognito returns application/x-amz-json-1.1, while the IRCC API normally
        # returns application/json. Both contain JSON and are accepted here.
        if ($contentType -notmatch '(?i)(application/(?:[a-z0-9.+-]*\+)?json|application/x-amz-json-1\.1)') {
            throw "$StepName returned an unexpected content type: $contentType. The service may be showing a maintenance page."
        }

        try {
            # For application/x-amz-json-1.1, some Windows PowerShell versions expose
            # Content as UTF-8 bytes instead of a decoded string.
            $rawContent = $response.Content
            if ($rawContent -is [byte[]]) {
                $jsonText = [Text.Encoding]::UTF8.GetString($rawContent)
            }
            elseif ($rawContent -is [System.Array] -and $rawContent.Count -gt 0 -and $rawContent[0] -is [byte]) {
                $jsonText = [Text.Encoding]::UTF8.GetString([byte[]]$rawContent)
            }
            else {
                $jsonText = [string]$rawContent
            }
            $jsonText = $jsonText.TrimStart([char]0xFEFF)
            $parsedResponse = ConvertFrom-Json -InputObject $jsonText
            return $parsedResponse
        }
        catch {
            throw "$StepName returned invalid JSON. The server response format may have changed."
        }
    }
    catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }

        if ($statusCode) {
            switch ($statusCode) {
                401 { throw "$StepName failed (HTTP 401): login or token was rejected." }
                403 { throw "$StepName failed (HTTP 403): access was denied." }
                429 { throw "$StepName failed (HTTP 429): too many requests. Please wait before trying again." }
                500 { throw "$StepName failed (HTTP 500): IRCC service error." }
                502 { throw "$StepName failed (HTTP 502): IRCC gateway error." }
                503 { throw "$StepName failed (HTTP 503): IRCC service is unavailable." }
                default { throw "$StepName failed (HTTP $statusCode)." }
            }
        }
        throw
    }
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Format-StatusValue {
    param($Value)
    if ($null -eq $Value) { return '未能读取' }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return '未能读取' }
        return $Value
    }
    foreach ($name in @('status', 'value', 'label')) {
        $nested = Get-PropertyValue $Value $name
        if ($null -ne $nested -and -not [string]::IsNullOrWhiteSpace([string]$nested)) {
            return [string]$nested
        }
    }
    return '未能读取'
}

function Format-DateOnly {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '未能读取' }
    try { return ([datetimeoffset]$Value).ToString('yyyy-MM-dd') } catch { return [string]$Value }
}

function Select-ApplicationRelation {
    param($Relations, [string]$ApplicationNumber)

    $items = @($Relations)
    if ($items.Count -eq 0) { throw 'The response does not contain an application relation.' }

    $needle = ($ApplicationNumber -replace '[\s-]', '').ToUpperInvariant()
    $matches = @()

    foreach ($item in $items) {
        # Search the individual relation only. This handles minor schema variations.
        $relationJson = $item | ConvertTo-Json -Depth 30 -Compress
        $normalizedJson = ($relationJson -replace '[\s-]', '').ToUpperInvariant()
        if ($normalizedJson.Contains($needle)) { $matches += $item }
    }

    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) { throw 'More than one relation matched the application number.' }
    if ($items.Count -eq 1) {
        Write-Warning 'The response did not expose an application number; using the only relation returned.'
        return $items[0]
    }
    throw 'Could not safely match the requested application among multiple relations.'
}

function Protect-LogFile {
    param([string]$Path)
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Get-Acl -LiteralPath $Path
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $identity,
            'FullControl',
            'Allow'
        )
        $acl.SetAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
    catch {
        Write-Warning 'Could not restrict log permissions. Do not store the folder in a shared or cloud-synced location.'
    }
}

Write-Host 'IRCC Tracker 安全查询工具' -ForegroundColor Cyan
Write-Host '凭据只用于本次登录，不会写入脚本或日志。' -ForegroundColor DarkGray
Write-Host ''

$trackerUsername = Read-RequiredText 'Tracker 用户名（通常为 UCI）'
$applicationNumber = Read-RequiredText 'Application Number'
$uciNumber = Read-RequiredText 'UCI'
$securePassword = Read-Host 'Tracker 密码（输入时不会显示）' -AsSecureString

# Remove UCI/application details from the visible terminal before making requests.
Clear-Host
Write-Host 'IRCC Tracker 安全查询工具' -ForegroundColor Cyan
Write-Host '已隐藏刚才输入的个人资料。' -ForegroundColor DarkGray
Write-Host ''

$bstr = [IntPtr]::Zero
$plainPassword = $null
$idToken = $null

try {
    Write-Host '正在登录 IRCC Tracker...' -ForegroundColor Cyan

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    $authBodyObject = @{
        AuthFlow = 'USER_PASSWORD_AUTH'
        ClientId = $ClientId
        AuthParameters = @{
            USERNAME = $trackerUsername
            PASSWORD = $plainPassword
        }
        ClientMetadata = @{}
    }
    $authBody = $authBodyObject | ConvertTo-Json -Depth 6 -Compress

    # Remove managed references as soon as the request body has been created/sent.
    $authResponse = Invoke-JsonPost -Uri $AuthUri `
        -Headers @{
            'X-Amz-Target' = 'AWSCognitoIdentityProviderService.InitiateAuth'
            'Content-Type' = 'application/x-amz-json-1.1'
        } `
        -Body $authBody `
        -StepName 'Login'

    $authBodyObject.AuthParameters.PASSWORD = $null
    $authBody = $null
    $plainPassword = $null

    # Some Windows PowerShell versions may enumerate a returned object. Normalize the
    # response by locating the Cognito envelope instead of assuming a scalar value.
    $authItems = @($authResponse)
    $authEnvelope = $null
    foreach ($item in $authItems) {
        if ($null -ne (Get-PropertyValue $item 'AuthenticationResult') -or
            $null -ne (Get-PropertyValue $item 'ChallengeName')) {
            $authEnvelope = $item
            break
        }
    }
    if ($null -eq $authEnvelope -and $authItems.Count -eq 1) {
        $authEnvelope = $authItems[0]
    }

    $authenticationResult = Get-PropertyValue $authEnvelope 'AuthenticationResult'
    $idToken = Get-PropertyValue $authenticationResult 'IdToken'
    if ([string]::IsNullOrWhiteSpace([string]$idToken)) {
        $challenge = Get-PropertyValue $authEnvelope 'ChallengeName'
        if ($challenge) { throw "Login requires an unsupported challenge: $challenge" }

        # Report structure only—never response values, tokens, sessions, or credentials.
        $itemCount = $authItems.Count
        $itemTypes = @($authItems | ForEach-Object { $_.GetType().FullName } | Select-Object -Unique) -join ', '
        if ([string]::IsNullOrWhiteSpace($itemTypes)) { $itemTypes = '(none)' }
        $envelopeKeys = '(envelope missing)'
        if ($null -ne $authEnvelope) {
            $envelopeKeys = @($authEnvelope.PSObject.Properties.Name) -join ', '
            if ([string]::IsNullOrWhiteSpace($envelopeKeys)) { $envelopeKeys = '(none)' }
        }
        $resultKeys = '(AuthenticationResult missing)'
        if ($null -ne $authenticationResult) {
            $resultKeys = @($authenticationResult.PSObject.Properties.Name) -join ', '
            if ([string]::IsNullOrWhiteSpace($resultKeys)) { $resultKeys = '(none)' }
        }
        throw "Login response contained no ID token. Item count: $itemCount. Item types: [$itemTypes]. Envelope fields: [$envelopeKeys]. AuthenticationResult fields: [$resultKeys]."
    }

    Write-Host '正在查询申请状态...' -ForegroundColor Cyan
    $queryBody = @{
        method = 'get-application-details'
        applicationNumber = $applicationNumber
        uci = $uciNumber
        isAgent = $false
    } | ConvertTo-Json -Depth 5 -Compress

    $statusResponse = Invoke-JsonPost -Uri $ApiUri `
        -Headers @{
            'Authorization' = "Bearer $idToken"
            'Content-Type' = 'application/json'
        } `
        -Body $queryBody `
        -StepName 'Status query'

    $idToken = $null
    $queryBody = $null

    $relations = Get-PropertyValue $statusResponse 'relations'
    $relation = Select-ApplicationRelation -Relations $relations -ApplicationNumber $applicationNumber

    $activities = Get-PropertyValue $relation 'activities'
    if ($null -eq $activities) { $activities = Get-PropertyValue $statusResponse 'activities' }
    if ($null -eq $activities) { throw 'The response does not contain an activities section.' }

    $eligibility = Format-StatusValue (Get-PropertyValue $activities 'eligibility')
    $medical = Format-StatusValue (Get-PropertyValue $activities 'medical')
    $background = Format-StatusValue (Get-PropertyValue $activities 'background')
    $biometrics = Format-StatusValue (Get-PropertyValue $activities 'biometrics')

    $history = Get-PropertyValue $relation 'history'
    if ($null -eq $history) { $history = Get-PropertyValue $statusResponse 'history' }
    $securityNodes = @(@($history) | Where-Object { (Get-PropertyValue $_ 'key') -eq 'Security' })

    if ($securityNodes.Count -gt 0) {
        $latestSecurityNode = $null
        $latestSecurityTime = [datetimeoffset]::MinValue
        foreach ($node in $securityNodes) {
            $rawDate = Get-PropertyValue $node 'dateCreated'
            try { $parsedDate = [datetimeoffset]$rawDate } catch { $parsedDate = [datetimeoffset]::MinValue }
            if ($null -eq $latestSecurityNode -or $parsedDate -gt $latestSecurityTime) {
                $latestSecurityNode = $node
                $latestSecurityTime = $parsedDate
            }
        }
        $securityDate = Format-DateOnly (Get-PropertyValue $latestSecurityNode 'dateCreated')
        $securityText = '检测到 Security 历史节点（不等同于确认进入深度安调）'
    }
    else {
        $securityDate = '未检测到'
        $securityText = '未检测到 Security 历史节点'
    }

    $appObject = Get-PropertyValue $statusResponse 'app'
    if ($null -eq $appObject) { $appObject = Get-PropertyValue $relation 'app' }
    $lastUpdated = Format-DateOnly (Get-PropertyValue $appObject 'lastUpdated')
    $checkedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $logEntry = @"
查询时间: $checkedAt
系统最后更新: $lastUpdated
Security: $securityText
Security 节点日期: $securityDate
--------------------------------------------------
资格审查 (Eligibility): $eligibility
医疗体检 (Medical): $medical
指纹录入 (Biometrics): $biometrics
背景调查 (Background): $background
备注: Security 内部节点不能单独证明已进入深度安调。
"@

    if ($KeepHistory -and (Test-Path -LiteralPath $LogPath)) {
        $existing = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
        $entries = @($existing -split '(?m)^### IRCC_STATUS_ENTRY ###\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $entries += $logEntry.Trim()
        if ($entries.Count -gt $MaxHistoryEntries) {
            $entries = @($entries | Select-Object -Last $MaxHistoryEntries)
        }
        $newLog = ($entries | ForEach-Object { "### IRCC_STATUS_ENTRY ###`r`n$($_.Trim())`r`n" }) -join "`r`n"
    }
    else {
        $newLog = "### IRCC_STATUS_ENTRY ###`r`n$($logEntry.Trim())`r`n"
    }

    Set-Content -LiteralPath $LogPath -Value $newLog -Encoding UTF8
    Protect-LogFile -Path $LogPath

    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host '查询成功' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host "系统最后更新: $lastUpdated"
    Write-Host "Security: $securityText"
    Write-Host "Security 节点日期: $securityDate"
    Write-Host "Eligibility: $eligibility"
    Write-Host "Medical: $medical"
    Write-Host "Biometrics: $biometrics"
    Write-Host "Background: $background"
    Write-Host '--------------------------------------------------'
    Write-Host "本地日志: $LogPath"
    Write-Host "最多保留最近 $MaxHistoryEntries 次结果。"
}
catch {
    Write-Host ''
    Write-Host "查询失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '没有写入新的状态日志。' -ForegroundColor DarkGray
    exit 1
}
finally {
    $idToken = $null
    $plainPassword = $null
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ($null -ne $securePassword) { $securePassword.Dispose() }
}
