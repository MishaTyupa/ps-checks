param(
    [Parameter(Mandatory = $False)]
    [System.Object[]]$endpoints
)

function Get-Parsed-Url {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$UrlCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$ExpectedContentCollection
    )

    $urlArray = @()

    for ($i = 0; $i -lt $UrlCollection.Length; $i++) {
        $Uri = [System.Uri]::new($UrlCollection[$i])
        $ExpectedContent = $ExpectedContentCollection[$i]
        $urlObject = [PSCustomObject]@{
            Host            = $Uri.Host
            Port            = $Uri.Port
            DnsSafeHost     = $Uri.DnsSafeHost
            AbsoluteUri     = $Uri.AbsoluteUri
            Protocol        = $Uri.Scheme + "://"
            ExpectedContent = $ExpectedContent
        }
        $urlArray += $urlObject
    }
    return $urlArray
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
        return 0
    }
    else {
        return 1
    }
}

function Show-Logs($gatheredLogs) {
    Write-Host "DNS Self-Check Logs:" $gatheredLogs.dnsSelfCheckLogs
    Write-Host "Services Check Logs:" $gatheredLogs.servicesCheckLogs
    Write-Host "Port Check Logs:" $gatheredLogs.portCheckLogs
    Write-Host "Domain Check Logs:" $gatheredLogs.domainCheckLogs
    Write-Host "Address Check Logs:" $gatheredLogs.addressCheckLogs
}
function Get-Response-Details($endpoint) {
    $responseDetails = @{}
    $endpointStatus = Invoke-WebRequest -Uri $endpoint -Verbose -UseBasicParsing 
    $endpointStatusCode = $endpointStatus | Select-Object -Expand StatusCode
    $endpointMatch = $endpointStatus.Content | Select-String -Pattern $ExpectedContentCollection[$i] | Select-Object -ExpandProperty Matches -First 1
    $responseDetails.endpointStatusCode += $endpointStatusCode
    $responseDetails.endpointMatchValue += $endpointMatch.Value
    return $responseDetails
}

function Test-Self-Check-DNS {
    $script:logs = @{}
    Write-Host "Testing if dns issue is present."
    $dnsIsOk = $False

    try {
        [System.Net.Dns]::GetHostEntry("kube-dns.kube-system.svc.cluster.local")
        $dnsIsOk = $True
    }
    catch {
        $logs.dnsSelfCheckLogs += $_.ScriptStackTrace
    }
    return $dnsIsOk
}

function Test-Service-Responds-By-Domain-Url {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$UrlCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$ExpectedContentCollection
    )

    Write-Host "Testing if service issue is present."

    $resultsArray = @()

    try {
        for ($i = 0; $i -lt $UrlCollection.Length; $i++) {
            $responseDetails = Get-Response-Details($UrlCollection[$i])
            if ($responseDetails.endpointStatusCode -eq 200 -And $responseDetails.endpointMatchValue -eq $ExpectedContentCollection[$i]) {
                $resultsArray += $True
            }
            else {
                $resultsArray += $False
            }
        }
        $serviceIsOk = Get-Final-Result($resultsArray) 
    }
    catch {
        $logs.servicesCheckLogs += $_.Exception.Response.StatusCode.Value__
    }
    return $serviceIsOk    
}

function Test-Port-Is-Opened {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$servicesCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$portsCollection
    )

    Write-Host "Testing if port issue is present."

    $resultsArray = @()

    try {
        for ($i = 0; $i -lt $portsCollection.Length; $i++) {
            $portStatus = nc -z -v -w5 $servicesCollection[$i] $portsCollection[$i] 2>&1

            Write-Host "Output! Port status is: $portStatus"

            $portMatch = $portStatus | Select-String "succeeded!"
            if (![string]::IsNullOrEmpty($portMatch)) {
                $resultsArray += $True
            }
            else {
                $resultsArray += $False
            }
        }
        $portIsOk = Get-Final-Result($resultsArray)
    }
    catch {
        $logs.portCheckLogs += $_.ScriptStackTrace
    }
    return $portIsOk
}

function Test-Domain-Address-Is-Resolved {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$servicesCollection
    )

    Write-Host "Testing if domain issue is present."
    $script:ipAddresses = @()
    $resultsArray = @()
    [ref]$ValidIP = [ipaddress]::None
    $serviceDNSValue = "Address"

    try {
        for ($i = 0; $i -lt $servicesCollection.Length; $i++) {
            $dnsCollection = nslookup $servicesCollection[$i]

            ForEach ($dns in (1..($dnsCollection.Count - 1))) {
                if ($dnsCollection[$dns - 1].Contains($servicesCollection[$i]) -And $dnsCollection[$dns].Contains($serviceDNSValue)) {
                    $ipAddresses += $dnsCollection[$dns].Split(":")[1].Trim()
                }
            }
    
            if (![string]::IsNullOrEmpty($ipAddresses[$i]) -And [ipaddress]::TryParse($ipAddresses[$i], $ValidIP)) {
                $resultsArray += $True
            }
            else {
                $resultsArray += $False
            }
        }
        $domainIsOk = Get-Final-Result($resultsArray)     
    }
    catch {
        $logs.domainCheckLogs += $_.ScriptStackTrace
    }
    return $domainIsOk
}

function Test-Service-Responds-As-Expected-By-IP {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$ProtocolsCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$PortsCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$ExpectedContentCollection
    )
    $resultsArray = @()

    try {
        Write-Host "Testing if Address issue is present."

        for ($i = 0; $i -lt $PortsCollection.Length; $i++) {
            $address = $ProtocolsCollection[$i] + $ipAddresses[$i] + ":" + $PortsCollection[$i]
            $responseDetails = Get-Response-Details($address)
            if ($responseDetails.endpointStatusCode -eq 200 -And $responseDetails.endpointMatchValue -eq $ExpectedContentCollection[$i]) {
                $resultsArray += $True
            }
            else {
                $resultsArray += $False
            }
        }
        $addressIsOk = Get-Final-Result($resultsArray)  
    }
    catch {
        $logs.addressCheckLogs += $_.ScriptStackTrace
    }
    return $addressIsOk
}

$results = @();
$parsedUrlCollection = Get-Parsed-Url -UrlCollection $endpoints.Url -ExpectedContentCollection $endpoints.ExpectedContent

$IsSelfDnsOk = Test-Self-Check-DNS 
Write-Host "DNS OK: $IsSelfDnsOk"
$results += $IsSelfDnsOk

$isServiceOk = Test-Service-Responds-By-Domain-Url -UrlCollection $parsedUrlCollection.AbsoluteUri -ExpectedContentCollection $parsedUrlCollection.ExpectedContent
Write-Host "Endpoints OK: $isServiceOk"
$results += $isServiceOk

$isPortOk = Test-Port-Is-Opened -ServicesCollection $parsedUrlCollection.DnsSafeHost -PortsCollection $parsedUrlCollection.Port
Write-Host "Ports OK: $isPortOk"
$results += $isPortOk

$isDomainOk = Test-Domain-Address-Is-Resolved -ServicesCollection $parsedUrlCollection.DnsSafeHost
Write-Host "Domains OK: $isDomainOk"
$results += $isDomainOk

$isAddressOk = Test-Service-Responds-As-Expected-By-IP -ProtocolsCollection $parsedUrlCollection.Protocol -PortsCollection $parsedUrlCollection.Port -ExpectedContentCollection $parsedUrlCollection.ExpectedContent
Write-Host "IP addresses OK: $isAddressOk"
$results += $isAddressOk

$finalResult = Get-Final-Result($results)
Show-Logs($logs)
Exit-Program($finalResult)