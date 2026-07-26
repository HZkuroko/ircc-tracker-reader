# IRCC Tracker Safe Windows v2.3 (merged edition)
# SPDX-License-Identifier: MIT
# Unofficial project; not affiliated with IRCC, Canada.ca, or AWS.
# Credentials, tokens and results are kept in memory and are not written to disk.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$AuthUri = [Uri]'https://cognito-idp.ca-central-1.amazonaws.com/'
$ApiUri = [Uri]'https://api.tracker-suivi.apps.cic.gc.ca/user'
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
        $inputValue = Read-RequiredText 'UCI (digits only or hyphenated format)'
        $normalized = $inputValue -replace '[\s-]', ''
        if ($normalized -match '^(\d{8}|\d{10})$') {
            return $normalized
        }
        Write-Host 'UCI must be 8 or 10 digits; hyphens are allowed and will be removed automatically.' -ForegroundColor Yellow
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
    if ($null -eq $Value) { return 'Unavailable' }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return 'Unavailable' }
        return $Value
    }
    foreach ($name in @('status', 'value', 'label')) {
        $nested = Get-PropertyValue $Value $name
        if ($null -ne $nested -and -not [string]::IsNullOrWhiteSpace([string]$nested)) {
            return [string]$nested
        }
    }
    return 'Unavailable'
}

function Format-DateOnly {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'Unavailable'
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

function Get-HttpErrorHint {
    param([string]$Stage, [int]$StatusCode)
    $isCognito = ($Stage -like '*Cognito*')
    switch ($StatusCode) {
        401 {
            if ($isCognito) { return 'Sign-in rejected (credentials, client ID, or auth flow).' }
            return 'The IRCC API rejected authorization (token invalid or expired).'
        }
        403 {
            if ($isCognito) { return 'Sign-in rejected, possibly by Cognito risk control.' }
            return 'The IRCC API/edge (WAF/CDN) blocked this request. Try a local Canadian network without VPN/proxy; scripted clients may still be blocked.'
        }
        429 { return 'Too many requests. Stop and wait before trying again.' }
        500 { return 'IRCC server error (Internal Server Error): server-side outage, no client-side fix.' }
        502 { return 'IRCC gateway error (Bad Gateway): server-side/edge outage.' }
        503 { return 'IRCC service unavailable: server-side outage.' }
        default { return '' }
    }
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
            $hint = Get-HttpErrorHint -Stage $Stage -StatusCode ([int]$response.StatusCode)
            if (-not [string]::IsNullOrWhiteSpace($hint)) {
                $script:LastDiagnostic.Hint = $hint
                throw "$Stage failed with HTTP $([int]$response.StatusCode) $($response.ReasonPhrase). $hint"
            }
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

function Show-Diagnostic {
    param($Diagnostic)
    if ($null -eq $Diagnostic) { return }

    Write-Host 'Security diagnostics (no credentials, tokens, or response body)' -ForegroundColor Yellow
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray
    foreach ($entry in $Diagnostic.GetEnumerator()) {
        Write-Host ("{0}: {1}" -f $entry.Key, $entry.Value)
    }
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray
}

function Show-LastDiagnostic {
    Show-Diagnostic $script:LastDiagnostic
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

function Select-RelationForUci {
    param($Relations, [string]$Uci)

    $items = @($Relations)
    if ($items.Count -eq 0 -or $null -eq $items[0]) {
        throw 'The application response contains no relation records.'
    }

    $needle = ConvertTo-NormalizedIdentifier $Uci
    $matched = @()
    foreach ($item in $items) {
        $candidate = Get-PropertyValue $item 'uci'
        if ((ConvertTo-NormalizedIdentifier ([string]$candidate)) -eq $needle) {
            $matched += $item
        }
    }

    if ($matched.Count -eq 1) { return $matched[0] }
    if ($matched.Count -gt 1) { throw 'More than one relation matched the UCI.' }
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
        $securityText = 'A Security history node was detected (this does not by itself confirm secondary/background security screening).'
    }
    else {
        $securityDate = 'Not detected'
        $securityText = 'No Security history node detected.'
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

function Invoke-SummaryPrecheck {
    param([hashtable]$ApiHeaders, [string]$ApplicationNumber)

    $status = [ordered]@{
        Outcome = 'Unknown'
        ReturnedAppCount = 0
        AppNumberInAccount = 'Unknown'
        Info = ''
        Diagnostic = $null
    }

    try {
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
            -Headers $ApiHeaders

        $status.Diagnostic = $script:LastDiagnostic

        $apps = @(Get-PropertyValue $profileResponse 'apps')
        if ($apps.Count -eq 0 -or $null -eq $apps[0]) {
            $status.Outcome = 'Empty'
            $status.ReturnedAppCount = 0
            $status.AppNumberInAccount = 'Not confirmed'
            $status.Info = 'Summary returned no applications (HTTP 200 with an empty list).'
            return [PSCustomObject]$status
        }

        $status.ReturnedAppCount = $apps.Count
        $needle = ConvertTo-NormalizedIdentifier $ApplicationNumber
        $matched = $false
        foreach ($app in $apps) {
            $candidate = Get-SummaryApplicationNumber $app
            if ((ConvertTo-NormalizedIdentifier $candidate) -eq $needle) {
                $matched = $true
                break
            }
        }

        if ($matched) {
            $status.Outcome = 'Matched'
            $status.AppNumberInAccount = 'Yes'
        }
        else {
            $status.Outcome = 'NoMatch'
            $status.AppNumberInAccount = 'No'
            $status.Info = 'The Application Number was not found among the returned applications.'
        }
        return [PSCustomObject]$status
    }
    catch {
        $status.Outcome = 'Error'
        $status.Info = $_.Exception.Message
        if ($null -eq $status.Diagnostic) { $status.Diagnostic = $script:LastDiagnostic }
        return [PSCustomObject]$status
    }
}

function Invoke-TrackerQuery {
    param(
        [string]$Uci,
        [string]$ApplicationNumber,
        [string]$PlainPassword
    )

    Write-Host 'Signing in to IRCC Tracker securely...' -ForegroundColor Cyan
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
        'Authorization'      = "Bearer $idToken"
        'Origin'             = $TrackerOrigin
        'Referer'            = "$TrackerOrigin/"
        'Accept-Language'    = 'en-CA,en;q=0.9'
        'Sec-Fetch-Site'     = 'same-site'
        'Sec-Fetch-Mode'     = 'cors'
        'Sec-Fetch-Dest'     = 'empty'
        'sec-ch-ua'          = '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"'
        'sec-ch-ua-mobile'   = '?0'
        'sec-ch-ua-platform' = '"Windows"'
    }

    # Stage 1: profile summary precheck. Informational only; never blocks stage 2.
    Write-Host 'Running profile summary precheck...' -ForegroundColor Cyan
    $summaryStatus = Invoke-SummaryPrecheck -ApiHeaders $apiHeaders -ApplicationNumber $ApplicationNumber

    # Stage 2: application details. Authoritative; always attempted regardless of stage 1.
    Write-Host 'Querying application details...' -ForegroundColor Cyan
    $detailOutcome = 'Error'
    $detailError = ''
    $detailResult = $null
    $detailDiagnostic = $null
    try {
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

        $detailDiagnostic = $script:LastDiagnostic
        $detailResult = Convert-DetailsToResult $detailsResponse $Uci
        $detailOutcome = 'Success'
        $detailsBody = $null
    }
    catch {
        $detailOutcome = 'Error'
        $detailError = $_.Exception.Message
        if ($null -eq $detailDiagnostic) { $detailDiagnostic = $script:LastDiagnostic }
    }

    # Scrub token-bearing references.
    $apiHeaders['Authorization'] = $null
    $idToken = $null

    return [PSCustomObject]@{
        Summary = $summaryStatus
        DetailOutcome = $detailOutcome
        DetailError = $detailError
        Details = $detailResult
        DetailDiagnostic = $detailDiagnostic
    }
}

function Show-Result {
    param($Outcome)

    Clear-Host
    Write-Host 'IRCC Tracker Query Result' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green

    $summary = $Outcome.Summary
    Write-Host ''
    Write-Host '--- Precheck (profile summary) ---' -ForegroundColor Cyan
    Write-Host "Summary outcome      : $($summary.Outcome)"
    Write-Host "Applications found   : $($summary.ReturnedAppCount)"
    Write-Host "App# in this account : $($summary.AppNumberInAccount)"
    if (-not [string]::IsNullOrWhiteSpace([string]$summary.Info)) {
        Write-Host "Note                 : $($summary.Info)"
    }

    Write-Host ''
    Write-Host '--- Application details ---' -ForegroundColor Cyan
    if ($Outcome.DetailOutcome -eq 'Success') {
        $r = $Outcome.Details
        Write-Host "Last updated  : $($r.LastUpdated)"
        Write-Host "Overall status: $($r.OverallStatus)"
        Write-Host "Eligibility   : $($r.Eligibility)"
        Write-Host "Medical       : $($r.Medical)"
        Write-Host "Biometrics    : $($r.Biometrics)"
        Write-Host "Background    : $($r.Background)"
        Write-Host "Security      : $($r.SecurityText)"
        Write-Host "Security date : $($r.SecurityDate)"
    }
    else {
        Write-Host "Details query failed: $($Outcome.DetailError)" -ForegroundColor Red
    }

    Write-Host '--------------------------------------------------'
    Write-Host 'This result is shown only in the current window and is not written to any file or cache.' -ForegroundColor DarkGray
}

Write-Host 'IRCC Tracker Safe Diagnostic Tool v2.3 (merged edition)' -ForegroundColor Cyan
Write-Host 'This edition keeps redacted diagnostics; it does not save credentials, tokens, results, or logs.' -ForegroundColor DarkGray
Write-Host ''

$uciNumber = Read-ValidatedUci
$applicationNumber = Read-RequiredText 'Application Number'
$securePassword = Read-Host 'Tracker password (input is hidden)' -AsSecureString

$bstr = [IntPtr]::Zero
$plainPassword = $null
$exitCode = 1

try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    Clear-Host
    Write-Host 'IRCC Tracker Safe Diagnostic Tool v2.3 (merged edition)' -ForegroundColor Cyan
    Write-Host 'Your entered personal details have been hidden.' -ForegroundColor DarkGray
    Write-Host ''

    New-HttpTransport

    $attempt = 1
    while ($attempt -le 2) {
        try {
            Write-Host "Query attempt $attempt / 2 (the second attempt runs only after you confirm manually)" -ForegroundColor DarkGray
            $outcome = Invoke-TrackerQuery `
                -Uci $uciNumber `
                -ApplicationNumber $applicationNumber `
                -PlainPassword $plainPassword
            Show-Result $outcome

            if ($outcome.DetailOutcome -eq 'Success') {
                $exitCode = 0
                break
            }

            Write-Host ''
            Write-Host "Application details did not succeed: $($outcome.DetailError)" -ForegroundColor Red
            if ($null -ne $outcome.Summary -and $outcome.Summary.Outcome -eq 'Error') {
                Write-Host ''
                Write-Host '[Profile summary stage diagnostic]' -ForegroundColor Yellow
                Show-Diagnostic $outcome.Summary.Diagnostic
            }
            Write-Host ''
            Write-Host '[Application details stage diagnostic]' -ForegroundColor Yellow
            Show-Diagnostic $outcome.DetailDiagnostic
        }
        catch {
            Write-Host ''
            Write-Host "Query failed: $($_.Exception.Message)" -ForegroundColor Red
            Show-LastDiagnostic
        }

        if ($attempt -ge 2) {
            Write-Host ''
            Write-Host 'Reached the maximum of two attempts; no further retry is allowed.' -ForegroundColor Yellow
            break
        }

        Write-Host ''
        Write-Host 'Press R to retry once manually; press Q to quit. No automatic retry.' -ForegroundColor Yellow
        do {
            $choice = (Read-Host 'Enter R or Q').Trim().ToUpperInvariant()
        } while ($choice -ne 'R' -and $choice -ne 'Q')

        if ($choice -eq 'Q') { break }
        $attempt++
        Write-Host ''
    }
}
catch {
    Write-Host ''
    Write-Host "Program error: $($_.Exception.Message)" -ForegroundColor Red
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
