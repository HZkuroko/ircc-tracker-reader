# IRCC Tracker Safe Windows v2.4.1 (merged, dual-endpoint edition; TLS hotfix)
# SPDX-License-Identifier: MIT
# Unofficial project; not affiliated with IRCC, Canada.ca, or AWS.
# Credentials, tokens and results are kept in memory and are not written to disk.
#
# v2.4 changes:
#   1. Detailed, privacy-safe Cognito error-type parsing (incl. x-amzn-errortype header).
#   2. Application-details parsing now tolerates alternative IRCC field names.
#   3. Deterministic TLS chain completion: the missing Entrust intermediate is
#      bundled and supplied during validation (scoped ONLY to the IRCC API hosts);
#      certificate verification is never disabled.
#   4. Dual-endpoint automatic fallback. The API host and its matching
#      Origin/Referer are switched together as a consistent pair.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$AuthUri = [Uri]'https://cognito-idp.ca-central-1.amazonaws.com/'
$ClientId = '3cfutv5ffd1i622g1tn6vton5r'
$ExpectedIssuer = 'https://cognito-idp.ca-central-1.amazonaws.com/ca-central-1_7OCkCncWC'
$BrowserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'

# Each endpoint pairs an API host with the matching front-end Origin/Referer.
# The API host and Origin are always switched together (never mixed).
# Endpoint A = the citizenship tracker site (no "ircc-").
# Endpoint B = the IRCC application status tracker site (with "ircc-").
# The tool tries A first, then falls back to B automatically.
$Endpoints = @(
    [PSCustomObject]@{
        Name   = 'A: tracker-suivi (no "ircc-")'
        ApiUri = [Uri]'https://api.tracker-suivi.apps.cic.gc.ca/user'
        Origin = 'https://tracker-suivi.apps.cic.gc.ca'
    },
    [PSCustomObject]@{
        Name   = 'B: ircc-tracker-suivi (with "ircc-")'
        ApiUri = [Uri]'https://api.ircc-tracker-suivi.apps.cic.gc.ca/user'
        Origin = 'https://ircc-tracker-suivi.apps.cic.gc.ca'
    }
)

# TLS chain completion is only ever applied to these known IRCC API hosts.
$script:ApiHostAllowList = @(
    'api.tracker-suivi.apps.cic.gc.ca',
    'api.ircc-tracker-suivi.apps.cic.gc.ca'
)

# Entrust OV TLS Issuing RSA CA 2 - the intermediate that signs the IRCC API
# leaf certificate but is omitted from the server-provided chain. Bundling it
# lets verification complete without relying on the OS fetching it via AIA.
# It must still chain to a trusted root already in the OS/framework trust store,
# so this does NOT weaken verification.
$EntrustIntermediatePem = @'
-----BEGIN CERTIFICATE-----
MIIGNjCCBB6gAwIBAgIRAIIHau9WPYiNkOddhKBQHE0wDQYJKoZIhvcNAQEMBQAw
XzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDE2MDQGA1UE
AxMtU2VjdGlnbyBQdWJsaWMgU2VydmVyIEF1dGhlbnRpY2F0aW9uIFJvb3QgUjQ2
MB4XDTI0MTIxMTAwMDAwMFoXDTI3MTIxMDIzNTk1OVowUTELMAkGA1UEBhMCQ0Ex
GDAWBgNVBAoTD0VudHJ1c3QgTGltaXRlZDEoMCYGA1UEAxMfRW50cnVzdCBPViBU
TFMgSXNzdWluZyBSU0EgQ0EgMjCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoC
ggGBAKo4ANoGIiqBGhTl3Wb2KYyxA/2xdrUR6VP+yFWqlm6BKHKib/XHiiE8UmZO
iUQzSWNXKWNRwuVrzq1gzFKLfU8FiV9rCRd+uW5JpzxLVO7Ojzpxj6/9P3oYpiO6
3T51mxqiEv9c2wKrO8aY3d4v/FnzTcbytQI2W4a2vKq+ZV/61Ph3+a26Y16KJMWg
LKKeRNEsOxoa/qr7ro8T0/6CzQhxKnVeuJMsOiVV45WqhFmUUx0FOFbH9wbPG7Fj
ddpkHGUxtdy433BVKvnwbemXDCHy+L1PhidcX3k+vYYD4xbuC3xApQcNBahpn6pG
9AGbbs5vjvs7LAFkewYG+NYH3JcF4f5sPhOFwlEoivxro57coEWzvIheq3dp8U3r
/8GyeK6cWK0fp+0w0JhckdKzMUo0Fxi2dlXsmcRch/Borkh9PXv3NGzs5/gmOYcO
Pa+46gyrlSHr4t7miFahk0Fpii8kBIZ1fBS/J0O4s85e9zgfMhZv0W5A2reGQQjB
9JFO/QIDAQABo4IBeTCCAXUwHwYDVR0jBBgwFoAUVnNYZJX5khqwEioEYnmhQBWI
IUkwHQYDVR0OBBYEFBfRrwB0+VX7UjfYhHYLWxKKUFrFMA4GA1UdDwEB/wQEAwIB
hjASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEF
BQcDAjATBgNVHSAEDDAKMAgGBmeBDAECAjBUBgNVHR8ETTBLMEmgR6BFhkNodHRw
Oi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNTZXJ2ZXJBdXRoZW50aWNh
dGlvblJvb3RSNDYuY3JsMIGEBggrBgEFBQcBAQR4MHYwTwYIKwYBBQUHMAKGQ2h0
dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1NlcnZlckF1dGhlbnRp
Y2F0aW9uUm9vdFI0Ni5wN2MwIwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3Rp
Z28uY29tMA0GCSqGSIb3DQEBDAUAA4ICAQBP/UQxKHBFQTfLCE6B7MkHDnFHqMlk
3boabJl0VxzIyLvMcgY6MVUwG0tOw/0aOPxKMwGTUQ+Mbj06XFQ9zwHP1rWpiGW3
SiJRhsGRY8BXTrU4l34Ysb30q77mTdjLXJfClBXRnVB0Gj/3eQmIIUSG16yjRKm4
g4MMXBK66Egq1VFHDvlSRRwZtiYzgXyv6umJMmtDtWqeyYXK5N1XGQ7UdlPUEpf5
/TI7zsFIR2PpgFmfedXReAtkwfiuwu2lVP5FcUMl9ZJyqSacV0Jd4PXkWKkcIWCb
a5KhD7TCCSyiLQWAbZLBG7TX+HBAaIAuCWPG5CaSK2H5qtIUlkrsw7keWBxW1Q6L
/j8N7vqb5KRAEDeBWIx9u5OqGORvRSo6FqZ7rq4opmXCMgLhJx4Cojccoj0i+p8o
Rfz32Yag1NPGBII2YNvgSbGKcDlpdxtvoKDPXnYn/2KBrJfCssWVadI83XbNc+n+
fdSupnjRzPY0KHx+V0glh3Qx14hYaGFJ0v4Of+kbrUyoHA1Ex5Lb0pZUU6vawIST
2X2bIDtDwJwObKgRRYPwUg+bo1Tp3/JL8uoYfb4ibbQHkMjYgGaartCpFeEZZbHa
ZIT+D2OnrLUsZuM4N5slfyi42i3NVnhmmduazaexMoWDATwL/8v2FH2t5Zrz7l++
qBfllYs4GyW26A==
-----END CERTIFICATE-----
'@

$script:LastDiagnostic = $null
$script:HttpClient = $null
$script:HttpHandler = $null
$script:ExtraCert = $null
$script:AddedIntermediate = $false

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

function Get-FirstProperty {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) {
        $value = Get-PropertyValue $Object $name
        if ($null -ne $value) { return $value }
    }
    return $null
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

function Initialize-ExtraCertificate {
    try {
        $begin = '-----BEGIN CERTIFICATE-----'
        $end = '-----END CERTIFICATE-----'
        $startIndex = $EntrustIntermediatePem.IndexOf($begin)
        $endIndex = $EntrustIntermediatePem.IndexOf($end)
        if ($startIndex -lt 0 -or $endIndex -lt 0) { return $false }
        $startIndex += $begin.Length
        $body = $EntrustIntermediatePem.Substring($startIndex, $endIndex - $startIndex)
        $body = $body -replace '\s', ''
        $der = [Convert]::FromBase64String($body)
        $script:ExtraCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($der)
        return $true
    }
    catch {
        $script:ExtraCert = $null
        return $false
    }
}

function Register-IntermediateCertificate {
    # Make the bundled Entrust intermediate available to the OS certificate chain
    # builder by placing it in the CurrentUser intermediate-CA store. This is NOT a
    # trust anchor (that would be the Root store); it only lets the chain builder
    # complete a chain when a server omits the intermediate. No administrator rights
    # are required, and it is fully removed again on exit. Non-fatal on failure.
    $script:AddedIntermediate = $false
    if ($null -eq $script:ExtraCert) { return }
    try {
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            [System.Security.Cryptography.X509Certificates.StoreName]::CertificateAuthority,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
        )
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        try {
            $existing = $store.Certificates.Find(
                [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $script:ExtraCert.Thumbprint,
                $false
            )
            if ($existing.Count -eq 0) {
                $store.Add($script:ExtraCert)
                $script:AddedIntermediate = $true
            }
        }
        finally {
            $store.Close()
        }
    }
    catch {
        # If the store cannot be written, stock validation still works for the
        # primary endpoint; only the secondary IRCC host might fail its handshake.
        $script:AddedIntermediate = $false
    }
}

function Unregister-IntermediateCertificate {
    # Leave the user's certificate store exactly as we found it.
    if (-not $script:AddedIntermediate -or $null -eq $script:ExtraCert) { return }
    try {
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            [System.Security.Cryptography.X509Certificates.StoreName]::CertificateAuthority,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
        )
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        try { $store.Remove($script:ExtraCert) } finally { $store.Close() }
    }
    catch { }
}

function New-HttpTransport {
    Add-Type -AssemblyName System.Net.Http

    $script:HttpHandler = [System.Net.Http.HttpClientHandler]::new()
    $script:HttpHandler.AllowAutoRedirect = $false
    $script:HttpHandler.AutomaticDecompression = (
        [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    )

    # NOTE: We intentionally do NOT set a ServerCertificateCustomValidationCallback.
    # In PowerShell that delegate runs on a worker thread with no attached runspace
    # and can throw, which aborts EVERY TLS handshake -- including the AWS Cognito
    # sign-in -- and surfaces as "The SSL connection could not be established".
    # Instead we complete the missing Entrust intermediate by importing it into the
    # CurrentUser intermediate-CA store (Register-IntermediateCertificate) so the OS
    # chain builder finds it during normal validation. Trust is NOT weakened: the
    # leaf certificate must still chain to a system-trusted root.

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

function Get-CognitoErrorInfo {
    param([string]$BodyText, [string]$HeaderErrorType)
    $code = ''
    $message = ''
    if (-not [string]::IsNullOrWhiteSpace($BodyText)) {
        try {
            $obj = ConvertFrom-Json -InputObject $BodyText
            foreach ($name in @('__type', 'code', 'Code')) {
                $value = Get-PropertyValue $obj $name
                if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { $code = [string]$value; break }
            }
            foreach ($name in @('message', 'Message', 'error_description', 'error')) {
                $value = Get-PropertyValue $obj $name
                if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { $message = [string]$value; break }
            }
        }
        catch { }
    }
    if ([string]::IsNullOrWhiteSpace($code) -and -not [string]::IsNullOrWhiteSpace($HeaderErrorType)) {
        $code = $HeaderErrorType
    }
    # Normalize "com.amazon.coral.service#NotAuthorizedException" and "X:..." forms.
    if ($code -match '#') { $code = ($code -split '#')[-1] }
    if ($code -match ':') { $code = ($code -split ':')[0] }
    $code = $code.Trim()
    return [PSCustomObject]@{ Code = $code; Message = $message }
}

function Get-CognitoFriendlyMessage {
    param([string]$Code, [string]$Message)
    $lower = ([string]$Message).ToLowerInvariant()
    $codeLabel = ''
    if (-not [string]::IsNullOrWhiteSpace($Code)) { $codeLabel = " ($Code)" }

    if ($lower -like '*unable to login because of security reasons*') {
        return "Sign-in was blocked by IRCC/Cognito security controls$codeLabel. This does NOT necessarily mean the password is wrong or the account is locked. Stop retrying and try the official tracker later."
    }

    switch ($Code) {
        'PasswordResetRequiredException' {
            return "IRCC/Cognito requires a password reset$codeLabel. Reset the Tracker password on the official site, then try again."
        }
        'UserNotConfirmedException' {
            return "The Tracker account is not confirmed$codeLabel. Finish account verification on the official site."
        }
        'UserNotFoundException' {
            # Do not reveal whether a particular UCI exists.
            return 'Incorrect UCI or Tracker password.'
        }
        'NotAuthorizedException' {
            if ($lower -like '*password attempts exceeded*') {
                return "Too many failed password attempts$codeLabel. Stop retrying and wait at least 15 minutes."
            }
            if ($lower -like '*incorrect username or password*') {
                return "Incorrect UCI or Tracker password$codeLabel."
            }
            return "Sign-in was not authorized$codeLabel. Usually this means an incorrect UCI or password; if you are sure they are correct, IRCC/Cognito may be applying risk control - stop retrying and try later."
        }
        { $_ -in @('LimitExceededException', 'TooManyFailedAttemptsException', 'TooManyRequestsException') } {
            return "IRCC/Cognito rejected the login: too many attempts$codeLabel. Stop retrying and wait at least 15 minutes."
        }
    }

    if ($lower -like '*incorrect username or password*') {
        return "Incorrect UCI or Tracker password$codeLabel."
    }
    if (-not [string]::IsNullOrWhiteSpace($Code)) {
        return "Cognito authentication failed$codeLabel."
    }
    return ''
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

            if ($Stage -like '*Cognito*') {
                $amznType = ''
                $headerValues = $null
                try {
                    if ($response.Headers.TryGetValues('x-amzn-errortype', [ref]$headerValues)) {
                        $amznType = @($headerValues)[0]
                    }
                }
                catch { }
                $cognitoInfo = Get-CognitoErrorInfo -BodyText $jsonText -HeaderErrorType $amznType
                if (-not [string]::IsNullOrWhiteSpace($cognitoInfo.Code)) {
                    $script:LastDiagnostic.CognitoErrorType = $cognitoInfo.Code
                }
                $friendly = Get-CognitoFriendlyMessage -Code $cognitoInfo.Code -Message $cognitoInfo.Message
                if (-not [string]::IsNullOrWhiteSpace($friendly)) {
                    $script:LastDiagnostic.Hint = $friendly
                    throw "$Stage failed with HTTP $([int]$response.StatusCode). $friendly"
                }
            }

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

    $relations = Get-FirstProperty $DetailsResponse @('relations', 'applications', 'apps', 'data')
    $relation = Select-RelationForUci $relations $Uci
    $activities = Get-FirstProperty $relation @('activities', 'activity')
    if ($null -eq $activities) { throw 'The response does not contain an activities section.' }

    $eligibility = Format-StatusValue (Get-FirstProperty $activities @('eligibility'))
    $medical = Format-StatusValue (Get-FirstProperty $activities @('medical'))
    $background = Format-StatusValue (Get-FirstProperty $activities @('background'))
    $biometrics = Format-StatusValue (Get-FirstProperty $activities @('biometrics', 'biometric'))

    $history = @(Get-FirstProperty $relation @('history', 'historyList', 'events'))
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

    $app = Get-FirstProperty $DetailsResponse @('app', 'application', 'summary')
    $lastUpdated = Format-DateOnly (Get-FirstProperty $app @('lastUpdated', 'lastUpdatedDate', 'updatedAt'))
    $overallStatus = Format-StatusValue (Get-FirstProperty $app @('status', 'appStatus'))

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
    param([Uri]$ApiUri, [hashtable]$ApiHeaders, [string]$ApplicationNumber, [string]$EndpointName)

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
            -Stage "IRCC profile summary [$EndpointName]" `
            -Uri $ApiUri `
            -JsonBody $profileBody `
            -RequestContentType 'application/json' `
            -Headers $ApiHeaders

        $status.Diagnostic = $script:LastDiagnostic

        $apps = @(Get-FirstProperty $profileResponse @('apps', 'applications', 'data'))
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

function Invoke-EndpointQuery {
    param($Endpoint, [string]$IdToken, [string]$Uci, [string]$ApplicationNumber)

    $apiHeaders = @{
        'Authorization'      = "Bearer $IdToken"
        'Origin'             = $Endpoint.Origin
        'Referer'            = "$($Endpoint.Origin)/"
        'Accept-Language'    = 'en-CA,en;q=0.9'
        'Sec-Fetch-Site'     = 'same-site'
        'Sec-Fetch-Mode'     = 'cors'
        'Sec-Fetch-Dest'     = 'empty'
        'sec-ch-ua'          = '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"'
        'sec-ch-ua-mobile'   = '?0'
        'sec-ch-ua-platform' = '"Windows"'
    }

    Write-Host "Running profile summary precheck ($($Endpoint.Name))..." -ForegroundColor Cyan
    $summaryStatus = Invoke-SummaryPrecheck -ApiUri $Endpoint.ApiUri -ApiHeaders $apiHeaders -ApplicationNumber $ApplicationNumber -EndpointName $Endpoint.Name

    Write-Host "Querying application details ($($Endpoint.Name))..." -ForegroundColor Cyan
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
            -Stage "IRCC application details [$($Endpoint.Name)]" `
            -Uri $Endpoint.ApiUri `
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

    $apiHeaders['Authorization'] = $null

    return [PSCustomObject]@{
        EndpointName = $Endpoint.Name
        Summary = $summaryStatus
        DetailOutcome = $detailOutcome
        DetailError = $detailError
        Details = $detailResult
        DetailDiagnostic = $detailDiagnostic
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

    $endpointResults = @()
    $usedEndpoint = $null
    $success = $false

    foreach ($endpoint in $Endpoints) {
        $result = Invoke-EndpointQuery `
            -Endpoint $endpoint `
            -IdToken $idToken `
            -Uci $Uci `
            -ApplicationNumber $ApplicationNumber
        $endpointResults += $result

        if ($result.DetailOutcome -eq 'Success') {
            $usedEndpoint = $endpoint.Name
            $success = $true
            break
        }

        Write-Host "Endpoint '$($endpoint.Name)' did not return application details; trying the next endpoint if available..." -ForegroundColor DarkYellow
    }

    $idToken = $null

    return [PSCustomObject]@{
        Success = $success
        UsedEndpoint = $usedEndpoint
        EndpointResults = $endpointResults
    }
}

function Show-SummarySection {
    param($Summary)
    Write-Host '--- Precheck (profile summary) ---' -ForegroundColor Cyan
    Write-Host "Summary outcome      : $($Summary.Outcome)"
    Write-Host "Applications found   : $($Summary.ReturnedAppCount)"
    Write-Host "App# in this account : $($Summary.AppNumberInAccount)"
    if (-not [string]::IsNullOrWhiteSpace([string]$Summary.Info)) {
        Write-Host "Note                 : $($Summary.Info)"
    }
}

function Show-Result {
    param($Outcome)

    Clear-Host
    Write-Host 'IRCC Tracker Query Result' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green

    if ($Outcome.Success) {
        $winner = $Outcome.EndpointResults | Where-Object { $_.DetailOutcome -eq 'Success' } | Select-Object -First 1
        Write-Host ''
        Write-Host "Endpoint used: $($Outcome.UsedEndpoint)" -ForegroundColor Green
        Write-Host ''
        Show-SummarySection $winner.Summary
        Write-Host ''
        Write-Host '--- Application details ---' -ForegroundColor Cyan
        $r = $winner.Details
        Write-Host "Last updated  : $($r.LastUpdated)"
        Write-Host "Overall status: $($r.OverallStatus)"
        Write-Host "Eligibility   : $($r.Eligibility)"
        Write-Host "Medical       : $($r.Medical)"
        Write-Host "Biometrics    : $($r.Biometrics)"
        Write-Host "Background    : $($r.Background)"
        Write-Host "Security      : $($r.SecurityText)"
        Write-Host "Security date : $($r.SecurityDate)"
        Write-Host '--------------------------------------------------'
        Write-Host 'This result is shown only in the current window and is not written to any file or cache.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host 'No endpoint returned application details. Per-endpoint results:' -ForegroundColor Red
    foreach ($endpointResult in $Outcome.EndpointResults) {
        Write-Host ''
        Write-Host "===== Endpoint: $($endpointResult.EndpointName) =====" -ForegroundColor Yellow
        Show-SummarySection $endpointResult.Summary
        Write-Host '--- Application details ---' -ForegroundColor Cyan
        Write-Host "Details query failed: $($endpointResult.DetailError)" -ForegroundColor Red
    }
    Write-Host '--------------------------------------------------'
    Write-Host 'This result is shown only in the current window and is not written to any file or cache.' -ForegroundColor DarkGray
}

Write-Host 'IRCC Tracker Safe Diagnostic Tool v2.4.1 (merged, dual-endpoint)' -ForegroundColor Cyan
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
    Write-Host 'IRCC Tracker Safe Diagnostic Tool v2.4.1 (merged, dual-endpoint)' -ForegroundColor Cyan
    Write-Host 'Your entered personal details have been hidden.' -ForegroundColor DarkGray
    Write-Host ''

    $null = Initialize-ExtraCertificate
    Register-IntermediateCertificate
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

            if ($outcome.Success) {
                $exitCode = 0
                break
            }

            Write-Host ''
            Write-Host 'Application details did not succeed on any endpoint.' -ForegroundColor Red
            foreach ($endpointResult in $outcome.EndpointResults) {
                Write-Host ''
                Write-Host "[Diagnostics for endpoint: $($endpointResult.EndpointName)]" -ForegroundColor Yellow
                if ($null -ne $endpointResult.Summary -and $endpointResult.Summary.Outcome -eq 'Error') {
                    Write-Host '[Profile summary stage diagnostic]' -ForegroundColor Yellow
                    Show-Diagnostic $endpointResult.Summary.Diagnostic
                }
                Write-Host '[Application details stage diagnostic]' -ForegroundColor Yellow
                Show-Diagnostic $endpointResult.DetailDiagnostic
            }
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
    Unregister-IntermediateCertificate
    if ($null -ne $script:ExtraCert) { $script:ExtraCert.Dispose() }
}

exit $exitCode
