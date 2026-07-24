# IRCC Tracker Safe Windows v2.0.1-diagnostic
# SPDX-License-Identifier: MIT
# Unofficial project; not affiliated with IRCC, Canada.ca, or AWS.
# Credentials, tokens and results are kept in memory and are not written to disk.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$AuthUri = [Uri]'https://cognito-idp.ca-central-1.amazonaws.com/'
$ApiUri = [Uri]'https://api.ircc-tracker-suivi.apps.cic.gc.ca/user'
$TrackerOrigin = 'https://ircc-tracker-suivi.apps.cic.gc.ca'
$ClientId = '3cfutv5ffd1i622g1tn6vton5r'
$ExpectedIssuer = 'https://cognito-idp.ca-central-1.amazonaws.com/ca-central-1_7OCkCncWC'
$BrowserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'
$script:LastDiagnostic = $null
$script:HttpClient = $null
$script:HttpHandler = $null

# Windows PowerShell 5.1 uses the .NET Framework network stack. Require TLS 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false

function Read-RequiredText {
    param([string]$Prompt)
    do {
        $value = (Read-Host $Prompt).Trim()
    } while ([string]::IsNullOrWhiteSpace($value))
    return $value
}

function Read-ValidatedUci {
    while ($true) {
        $inputValue = Read-RequiredText 'UCI（可输入纯数字或带连字符格式）'
        $normalized = $inputValue -replace '[\s-]', ''
        if ($normalized -match '^(\d{8}|\d{10})$') {
            return $normalized
        }
        Write-Host 'UCI 必须是 8 位或 10 位数字；可以带连字符，程序会自动移除。' -ForegroundColor Yellow
    }
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-NormalizedIdentifier {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value -replace '[\s-]', '').ToUpperInvariant())
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
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return '未能读取'
    }
    try { return ([datetimeoffset]$Value).ToString('yyyy-MM-dd') }
    catch { return [string]$Value }
}

function New-HttpTransport {
    Add-Type -AssemblyName System.Net.Http

    $script:HttpHandler = [System.Net.Http.HttpClientHandler]::new()
    $script:HttpHandler.AllowAutoRedirect = $false
    $script:HttpHandler.AutomaticDecompression = (
        [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    )

    $script:HttpClient = [System.Net.Http.HttpClient]::new($script:HttpHandler)
    $script:HttpClient.Timeout = [TimeSpan]::FromSeconds(35)
    $null = $script:HttpClient.DefaultRequestHeaders.TryAddWithoutValidation(
        'User-Agent', $BrowserUserAgent
    )
}

function Test-JsonMediaType {
    param([string]$MediaType)
    if ([string]::IsNullOrWhiteSpace($MediaType)) { return $false }
    return ($MediaType -match '(?i)^(application/json|application/[a-z0-9.+-]+\+json|application/x-amz-json-1\.1)$')
}

function Get-SafeInnerExceptionMessage {
    param([Exception]$Exception)
    if ($null -ne $Exception.InnerException) {
        return "$($Exception.InnerException.GetType().FullName): $($Exception.InnerException.Message)"
    }
    return '(none)'
}

function Invoke-JsonPost {
    param(
        [string]$Stage,
        [Uri]$Uri,
        [string]$JsonBody,
        [string]$RequestContentType,
        [hashtable]$Headers
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $request = $null
    $response = $null
    $script:LastDiagnostic = [ordered]@{
        Stage = $Stage
        Endpoint = "$($Uri.Scheme)://$($Uri.Host)$($Uri.AbsolutePath)"
        Transport = 'System.Net.Http.HttpClient'
        PowerShell = $PSVersionTable.PSVersion.ToString()
        TLS = [Net.ServicePointManager]::SecurityProtocol.ToString()
        AttemptResult = 'pending'
        HttpStatus = '(no response)'
        ContentType = '(no response)'
        ResponseCharacters = 0
        DurationMs = 0
        ExceptionType = '(none)'
        ExceptionMessage = '(none)'
        InnerException = '(none)'
    }

    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post,
            $Uri
        )
        $request.Content = [System.Net.Http.StringContent]::new(
            $JsonBody,
            [Text.Encoding]::UTF8,
            $RequestContentType
        )

        $null = $request.Headers.TryAddWithoutValidation('Accept', 'application/json')
        $null = $request.Headers.TryAddWithoutValidation('Cache-Control', 'no-store')
        $null = $request.Headers.TryAddWithoutValidation('Pragma', 'no-cache')
        foreach ($key in $Headers.Keys) {
            $null = $request.Headers.TryAddWithoutValidation($key, [string]$Headers[$key])
        }

        $response = $script:HttpClient.SendAsync($request).GetAwaiter().GetResult()
        $jsonText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $stopwatch.Stop()

        $mediaType = ''
        if ($null -ne $response.Content.Headers.ContentType) {
            $mediaType = [string]$response.Content.Headers.ContentType.MediaType
        }

        $script:LastDiagnostic.HttpStatus = "$([int]$response.StatusCode) $($response.ReasonPhrase)"
        $script:LastDiagnostic.ContentType = $mediaType
        $script:LastDiagnostic.ResponseCharacters = $jsonText.Length
        $script:LastDiagnostic.DurationMs = $stopwatch.ElapsedMilliseconds

        if (-not $response.IsSuccessStatusCode) {
            $script:LastDiagnostic.AttemptResult = 'HTTP error'
            throw "$Stage failed with HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)."
        }

        if (-not (Test-JsonMediaType $mediaType)) {
            $script:LastDiagnostic.AttemptResult = 'unexpected content type'
            throw "$Stage returned an unexpected content type: $mediaType."
        }

        try {
            $parsed = ConvertFrom-Json -InputObject $jsonText
        }
        catch {
            $script:LastDiagnostic.AttemptResult = 'invalid JSON'
            throw "$Stage returned invalid JSON or a changed response format."
        }

        $script:LastDiagnostic.AttemptResult = 'success'
        return $parsed
    }
    catch {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
            $script:LastDiagnostic.DurationMs = $stopwatch.ElapsedMilliseconds
        }
        if ($script:LastDiagnostic.AttemptResult -eq 'pending') {
            $script:LastDiagnostic.AttemptResult = 'transport error'
        }
        $script:LastDiagnostic.ExceptionType = $_.Exception.GetType().FullName
        $script:LastDiagnostic.ExceptionMessage = $_.Exception.Message
        $script:LastDiagnostic.InnerException = Get-SafeInnerExceptionMessage $_.Exception
        throw
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $request) { $request.Dispose() }
    }
}

function Show-LastDiagnostic {
    if ($null -eq $script:LastDiagnostic) { return }

    Write-Host ''
    Write-Host '安全诊断信息（不包含凭据、Token 或响应正文）' -ForegroundColor Yellow
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray
    foreach ($entry in $script:LastDiagnostic.GetEnumerator()) {
        Write-Host ("{0}: {1}" -f $entry.Key, $entry.Value)
    }
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray
}

function Read-JwtPayload {
    param([string]$Token)

    $parts = $Token.Split('.')
    if ($parts.Length -ne 3) { throw 'Cognito returned a token that is not a three-part JWT.' }

    $encoded = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($encoded.Length % 4) {
        0 { }
        2 { $encoded += '==' }
        3 { $encoded += '=' }
        default { throw 'Cognito returned an invalid JWT payload encoding.' }
    }

    $payloadJson = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($encoded)
    )
    return (ConvertFrom-Json -InputObject $payloadJson)
}

function Test-IdToken {
    param([string]$Token)

    $payload = Read-JwtPayload $Token
    $tokenUse = [string](Get-PropertyValue $payload 'token_use')
    $audience = [string](Get-PropertyValue $payload 'aud')
    $issuer = [string](Get-PropertyValue $payload 'iss')
    $expiry = Get-PropertyValue $payload 'exp'

    $script:LastDiagnostic = [ordered]@{
        Stage = 'Local JWT validation'
        Endpoint = '(local only)'
        Transport = '(none)'
        PowerShell = $PSVersionTable.PSVersion.ToString()
        TokenUseIsId = ($tokenUse -eq 'id')
        AudienceMatchesClient = ($audience -eq $ClientId)
        IssuerMatchesExpectedPool = ($issuer -eq $ExpectedIssuer)
        ExpiryPresent = ($null -ne $expiry)
    }

    if ($tokenUse -ne 'id') { throw 'Cognito token_use is not id.' }
    if ($audience -ne $ClientId) { throw 'Cognito token audience does not match the expected client.' }
    if ($issuer -ne $ExpectedIssuer) { throw 'Cognito token issuer does not match the expected user pool.' }
    if ($null -eq $expiry) { throw 'Cognito token has no expiry claim.' }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ([Int64]$expiry -le $now) { throw 'Cognito returned an expired ID token.' }
    return $true
}

function Get-SummaryApplicationNumber {
    param($Application)
    foreach ($name in @('appNum', 'appNumber', 'applicationNumber', 'id')) {
        $value = Get-PropertyValue $Application $name
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }
    return $null
}

function Confirm-ApplicationInProfile {
    param($ProfileResponse, [string]$ApplicationNumber)

    $apps = @(Get-PropertyValue $ProfileResponse 'apps')
    if ($apps.Count -eq 0 -or $null -eq $apps[0]) {
        $script:LastDiagnostic = [ordered]@{
            Stage = 'Application matching'
            Result = 'Profile summary returned no applications'
            RequestedApplication = '(redacted)'
        }
        throw 'Profile summary did not return any applications.'
    }

    $needle = ConvertTo-NormalizedIdentifier $ApplicationNumber
    foreach ($app in $apps) {
        $candidate = Get-SummaryApplicationNumber $app
        if ((ConvertTo-NormalizedIdentifier $candidate) -eq $needle) {
            return $true
        }
    }

    $script:LastDiagnostic = [ordered]@{
        Stage = 'Application matching'
        Result = 'No exact application-number match'
        ReturnedApplicationCount = $apps.Count
        RequestedApplication = '(redacted)'
    }
    throw 'The requested Application Number was not found in the authenticated profile.'
}

function Select-RelationForUci {
    param($Relations, [string]$Uci)

    $items = @($Relations)
    if ($items.Count -eq 0 -or $null -eq $items[0]) {
        throw 'The application response contains no relation records.'
    }

    $needle = ConvertTo-NormalizedIdentifier $Uci
    $matches = @()
    foreach ($item in $items) {
        $candidate = Get-PropertyValue $item 'uci'
        if ((ConvertTo-NormalizedIdentifier ([string]$candidate)) -eq $needle) {
            $matches += $item
        }
    }

    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) { throw 'More than one relation matched the UCI.' }
    if ($items.Count -eq 1) { return $items[0] }
    throw 'Could not safely match a relation to the UCI.'
}

function Convert-DetailsToResult {
    param($DetailsResponse, [string]$Uci)

    $relations = Get-PropertyValue $DetailsResponse 'relations'
    $relation = Select-RelationForUci $relations $Uci
    $activities = Get-PropertyValue $relation 'activities'
    if ($null -eq $activities) { throw 'The response does not contain an activities section.' }

    $eligibility = Format-StatusValue (Get-PropertyValue $activities 'eligibility')
    $medical = Format-StatusValue (Get-PropertyValue $activities 'medical')
    $background = Format-StatusValue (Get-PropertyValue $activities 'background')
    $biometrics = Format-StatusValue (Get-PropertyValue $activities 'biometrics')

    $history = @(Get-PropertyValue $relation 'history')
    $securityNodes = @($history | Where-Object {
        (Get-PropertyValue $_ 'key') -eq 'Security'
    })

    if ($securityNodes.Count -gt 0) {
        $latestNode = $null
        $latestTime = [datetimeoffset]::MinValue
        foreach ($node in $securityNodes) {
            $rawDate = Get-PropertyValue $node 'dateCreated'
            try { $parsedDate = [datetimeoffset]$rawDate }
            catch { $parsedDate = [datetimeoffset]::MinValue }
            if ($null -eq $latestNode -or $parsedDate -gt $latestTime) {
                $latestNode = $node
                $latestTime = $parsedDate
            }
        }
        $securityDate = Format-DateOnly (Get-PropertyValue $latestNode 'dateCreated')
        $securityText = '检测到 Security 历史节点（不等同于确认进入深度安调）'
    }
    else {
        $securityDate = '未检测到'
        $securityText = '未检测到 Security 历史节点'
    }

    $app = Get-PropertyValue $DetailsResponse 'app'
    $lastUpdated = Format-DateOnly (Get-PropertyValue $app 'lastUpdated')
    $overallStatus = Format-StatusValue (Get-PropertyValue $app 'status')

    return [PSCustomObject]@{
        LastUpdated = $lastUpdated
        OverallStatus = $overallStatus
        Eligibility = $eligibility
        Medical = $medical
        Biometrics = $biometrics
        Background = $background
        SecurityText = $securityText
        SecurityDate = $securityDate
    }
}

function Invoke-TrackerQuery {
    param(
        [string]$Uci,
        [string]$ApplicationNumber,
        [string]$PlainPassword
    )

    Write-Host '正在安全登录 IRCC Tracker...' -ForegroundColor Cyan
    $authBodyObject = @{
        AuthFlow = 'USER_PASSWORD_AUTH'
        ClientId = $ClientId
        AuthParameters = @{
            USERNAME = $Uci
            PASSWORD = $PlainPassword
        }
        ClientMetadata = @{}
    }
    $authBody = $authBodyObject | ConvertTo-Json -Depth 6 -Compress

    $authResponse = Invoke-JsonPost `
        -Stage 'Cognito login' `
        -Uri $AuthUri `
        -JsonBody $authBody `
        -RequestContentType 'application/x-amz-json-1.1' `
        -Headers @{
            'X-Amz-Target' = 'AWSCognitoIdentityProviderService.InitiateAuth'
            'X-Amz-User-Agent' = 'aws-amplify/5.0.4 js'
        }

    $authBodyObject.AuthParameters.PASSWORD = $null
    $authBody = $null

    $authenticationResult = Get-PropertyValue $authResponse 'AuthenticationResult'
    $idToken = [string](Get-PropertyValue $authenticationResult 'IdToken')
    if ([string]::IsNullOrWhiteSpace($idToken)) {
        $challenge = Get-PropertyValue $authResponse 'ChallengeName'
        if ($challenge) { throw "Login requires an unsupported challenge: $challenge" }
        throw 'Cognito login returned no ID token.'
    }

    $null = Test-IdToken $idToken

    $apiHeaders = @{
        'Authorization' = "Bearer $idToken"
        'Origin' = $TrackerOrigin
        'Referer' = "$TrackerOrigin/"
        'Accept-Language' = 'en-CA,en;q=0.9'
    }

    Write-Host '正在读取账号申请列表...' -ForegroundColor Cyan
    $profileBody = @{
        method = 'get-profile-summary'
        startIndex = 0
        limit = 500
        lob = ''
        lastActivityDecs = $false
        searchFilter = ''
        statusFilter = ''
        isAgent = $false
    } | ConvertTo-Json -Depth 5 -Compress

    $profileResponse = Invoke-JsonPost `
        -Stage 'IRCC profile summary' `
        -Uri $ApiUri `
        -JsonBody $profileBody `
        -RequestContentType 'application/json' `
        -Headers $apiHeaders

    $null = Confirm-ApplicationInProfile $profileResponse $ApplicationNumber

    Write-Host '正在查询申请状态...' -ForegroundColor Cyan
    $detailsBody = @{
        method = 'get-application-details'
        applicationNumber = $ApplicationNumber
        uci = $Uci
        isAgent = $false
    } | ConvertTo-Json -Depth 5 -Compress

    $detailsResponse = Invoke-JsonPost `
        -Stage 'IRCC application details' `
        -Uri $ApiUri `
        -JsonBody $detailsBody `
        -RequestContentType 'application/json' `
        -Headers $apiHeaders

    # Remove token-bearing headers and request bodies from managed references.
    $apiHeaders['Authorization'] = $null
    $idToken = $null
    $profileBody = $null
    $detailsBody = $null

    return (Convert-DetailsToResult $detailsResponse $Uci)
}

function Show-Result {
    param($Result)

    Clear-Host
    Write-Host 'IRCC Tracker 查询结果' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host "系统最后更新: $($Result.LastUpdated)"
    Write-Host "整体状态: $($Result.OverallStatus)"
    Write-Host "Eligibility: $($Result.Eligibility)"
    Write-Host "Medical: $($Result.Medical)"
    Write-Host "Biometrics: $($Result.Biometrics)"
    Write-Host "Background: $($Result.Background)"
    Write-Host "Security: $($Result.SecurityText)"
    Write-Host "Security 节点日期: $($Result.SecurityDate)"
    Write-Host '--------------------------------------------------'
    Write-Host '本次结果仅显示在当前窗口，不会写入文件或缓存。' -ForegroundColor DarkGray
}

Write-Host 'IRCC Tracker 安全诊断工具 v2.0.1' -ForegroundColor Cyan
Write-Host '本版本保留脱敏诊断信息；不保存凭据、Token、结果或日志。' -ForegroundColor DarkGray
Write-Host ''

$uciNumber = Read-ValidatedUci
$applicationNumber = Read-RequiredText 'Application Number'
$securePassword = Read-Host 'Tracker 密码（输入时不会显示）' -AsSecureString

$bstr = [IntPtr]::Zero
$plainPassword = $null
$exitCode = 1

try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    Clear-Host
    Write-Host 'IRCC Tracker 安全诊断工具 v2.0.1' -ForegroundColor Cyan
    Write-Host '已隐藏刚才输入的个人资料。' -ForegroundColor DarkGray
    Write-Host ''

    New-HttpTransport

    $attempt = 1
    while ($attempt -le 2) {
        try {
            Write-Host "查询尝试 $attempt / 2（第二次只会在你手动确认后执行）" -ForegroundColor DarkGray
            $result = Invoke-TrackerQuery `
                -Uci $uciNumber `
                -ApplicationNumber $applicationNumber `
                -PlainPassword $plainPassword
            Show-Result $result
            $exitCode = 0
            break
        }
        catch {
            Write-Host ''
            Write-Host "查询失败：$($_.Exception.Message)" -ForegroundColor Red
            Show-LastDiagnostic

            if ($attempt -ge 2) {
                Write-Host '已达到最多两次尝试，本次不再允许重试。' -ForegroundColor Yellow
                break
            }

            Write-Host ''
            Write-Host '按 R 手动重试一次；按 Q 退出。不会自动重试。' -ForegroundColor Yellow
            do {
                $choice = (Read-Host '请输入 R 或 Q').Trim().ToUpperInvariant()
            } while ($choice -ne 'R' -and $choice -ne 'Q')

            if ($choice -eq 'Q') { break }
            $attempt++
            Write-Host ''
        }
    }
}
catch {
    Write-Host ''
    Write-Host "程序错误：$($_.Exception.Message)" -ForegroundColor Red
    Show-LastDiagnostic
}
finally {
    $plainPassword = $null
    $uciNumber = $null
    $applicationNumber = $null
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ($null -ne $securePassword) { $securePassword.Dispose() }
    if ($null -ne $script:HttpClient) { $script:HttpClient.Dispose() }
    if ($null -ne $script:HttpHandler) { $script:HttpHandler.Dispose() }
}

exit $exitCode
