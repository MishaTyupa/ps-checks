param(
    [Parameter(Mandatory = $False)]
    [System.Object[]]$endpoints
)

function Get-Parsed-Url {
    param(
        [Parameter(Mandatory = $True)]
        [string]$Url,
        [Parameter(Mandatory = $True)]
        [string]$ExpectedContent
    ) 
 
    $Uri = [System.Uri]::new($Url)
   
    $urlObject = [PSCustomObject]@{
        Host            = $Uri.Host
        Port            = $Uri.Port
        DnsSafeHost     = $Uri.DnsSafeHost
        AbsoluteUri     = $Uri.AbsoluteUri
        Protocol        = $Uri.Scheme + "://"
        ExpectedContent = $ExpectedContent
    } 
 
    return $urlObject 
}

function Get-Final-Result($resultsArray) {
    $finalResult = $False
    if (!($resultsArray -contains $False)) {
        $finalResult = $True
    }
    return $finalResult
}

function Exit-Program($finalResult) {
    if ($finalResult -eq $True) {
        exit 0
    }
    else {
        exit 1
    }
}

function Show-Logs($gatheredLogs) {
    foreach ($log in $gatheredLogs) {
        if (![string]::IsNullOrEmpty($log)) {
            Write-Host "Error logs:" $log
        }
    }
}

function Get-Response-Details {
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Endpoint,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $ExpectedContent
    )

    $responseDetails = @{}
    $endpointStatus = Invoke-WebRequest -Uri $Endpoint -Verbose -UseBasicParsing
    $endpointStatusCode = $endpointStatus | Select-Object -Expand StatusCode
    $endpointMatch = $endpointStatus.RawContent | Select-String -Pattern $ExpectedContent | Select-Object -ExpandProperty Matches -First 1
    $responseDetails.endpointStatusCode += $endpointStatusCode
    $responseDetails.endpointMatchValue += $endpointMatch.Value
    return $responseDetails
}

function Test-Self-Check-DNS {
    Write-Host "DNS container resolution self-check"
    $dnsIsOk = $False

    try {
        $null = [System.Net.Dns]::GetHostEntry("kube-dns.kube-system.svc.cluster.local")
        $dnsIsOk = $True
    }
    catch {
        $script:logs += $_.ScriptStackTrace
    }
    return $dnsIsOk
}

function Test-Service-Responds-By-Domain-Url {
    param(
        [Parameter(Mandatory = $True)]
        [string]$Url,
        [Parameter(Mandatory = $True)]
        [string]$ExpectedContent
    )

    Write-Host "Testing endpoint"

    $serviceIsOk = $False
    try {
            $responseDetails = Get-Response-Details -Endpoint $Url -ExpectedContent $ExpectedContent
            if ($responseDetails.endpointStatusCode -eq 200 -And $responseDetails.endpointMatchValue -eq $ExpectedContent) {
                $serviceIsOk = $True
            }
    }
    catch {
        $script:logs += $_.Exception.Response.StatusCode.Value__
    }
    return $serviceIsOk    
}

function Test-Port-Is-Opened {
    param(
        [Parameter(Mandatory = $True)]
        [string]$Service,
        [Parameter(Mandatory = $True)]
        [string]$Port
    )

    Write-Host "Testing if TCP port is opened"

    $portIsOk = $False
    try {
            $portStatus = nc -z -v -w5 $Service $Port 2>&1

            Write-Host "Output! Port status is: $portStatus"

            $portMatch = $portStatus | Select-String "succeeded!"
            if (![string]::IsNullOrEmpty($portMatch)) {
                $portIsOk = $True
            }
    }
    catch {
        $script:logs += $_.ScriptStackTrace
    }
    return $portIsOk
}

function Test-Domain-Address-Is-Resolved {
    param(
        [Parameter(Mandatory = $True)]
        [string]$Service
    )

    Write-Host "Testing DNS resolution of endpoint"

    [ref]$ValidIP = [ipaddress]::None
    $serviceDNSValue = "Address"
    $domainIsOk = $False
    try {
            $dnsCollection = nslookup $Service

            ForEach ($dns in (1..($dnsCollection.Count - 1))) {
                if ($dnsCollection[$dns - 1].Contains($Service) -And $dnsCollection[$dns].Contains($serviceDNSValue)) {
                    $script:ipAddress = $dnsCollection[$dns].Split(":")[1].Trim()
                }
            }
    
            if (![string]::IsNullOrEmpty($ipAddress) -And [ipaddress]::TryParse($ipAddress, $ValidIP)) {
                $domainIsOk = $True
            }              
    }
    catch {
        $script:logs += $_.ScriptStackTrace
    }
    return $domainIsOk
}

function Test-Service-Responds-As-Expected-By-IP {
    param(
        [Parameter(Mandatory = $True)]
        [string]$Protocol,
        [Parameter(Mandatory = $True)]
        [string]$Port,
        [Parameter(Mandatory = $True)]
        [string]$ExpectedContent
    )
    $addressIsOk = $False
    try {
        Write-Host "Checking endpoint by it's IP"

            $address = $Protocol + $ipAddress + ":" + $Port
            Write-Host "Output! Service Address is: $address"
            $responseDetails = Get-Response-Details -Endpoint $address -ExpectedContent $ExpectedContent
            if ($responseDetails.endpointStatusCode -eq 200 -And $responseDetails.endpointMatchValue -eq $ExpectedContent) {
                $addressIsOk = $True
            }
    }
    catch {
        $script:logs += $_.ScriptStackTrace
    }
    return $addressIsOk
}

$serviceCheckResults = @();
$portCheckResults = @();
$domainCheckResults = @();
$addressCheckResults = @();
$results = @();
$logs = @();
$endpointsData = @($endpoints | ForEach-Object { Get-Parsed-Url -Url $_.Url -ExpectedContent $_.ExpectedContent})

$IsSelfDnsOk = Test-Self-Check-DNS 
Write-Host "DNS is OK: $IsSelfDnsOk"
$results += $IsSelfDnsOk

foreach ($endpointData in $endpointsData) {
    $serviceCheckResults += Test-Service-Responds-By-Domain-Url -Url $endpointData.AbsoluteUri -ExpectedContent $endpointData.ExpectedContent
    $portCheckResults += Test-Port-Is-Opened -Service $endpointData.DnsSafeHost -Port $endpointData.Port
    $domainCheckResults += Test-Domain-Address-Is-Resolved -Service $endpointData.DnsSafeHost
    $addressCheckResults += Test-Service-Responds-As-Expected-By-IP -Protocol $endpointData.Protocol -Port $endpointData.Port -ExpectedContent $endpointData.ExpectedContent
}

$AreServicesOk = Get-Final-Result($serviceCheckResults)
Write-Host "Services are OK: $AreServicesOk"
$results += $AreServicesOk

$ArePortsOk = Get-Final-Result($portCheckResults)
Write-Host "Ports are OK: $ArePortsOk"
$results += $ArePortsOk

$AreDomainsOk = Get-Final-Result($domainCheckResults)
Write-Host "Endpoints DNS resolution is OK: $AreDomainsOk"
$results += $AreDomainsOk

$AreAddressesOk = Get-Final-Result($addressCheckResults)
Write-Host "IP addresses are OK: $AreAddressesOk"
$results += $AreAddressesOk

$finalResult = Get-Final-Result($results)
Show-Logs($logs)
Exit-Program($finalResult)