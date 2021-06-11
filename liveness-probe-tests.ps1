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
  foreach ($log in $gatheredLogs) {
      if(![string]::IsNullOrEmpty($log)){
          Write-Host "Error logs:" $log
      }
  }
}

function Get-Response-Details($endpoint) {
    $responseDetails = @{}
    $endpointStatus = Invoke-WebRequest -Uri $endpoint -Verbose -UseBasicParsing
    $endpointStatusCode = $endpointStatus | Select-Object -Expand StatusCode
    $endpointMatch = $endpointStatus.RawContent | Select-String -Pattern $ExpectedContentCollection[$i] | Select-Object -ExpandProperty Matches -First 1
    $responseDetails.endpointStatusCode += $endpointStatusCode
    $responseDetails.endpointMatchValue += $endpointMatch.Value
    return $responseDetails
}

function Test-Self-Check-DNS {
    Write-Host "Testing if dns issue is present."
    $dnsIsOk = $False

    try {
        [System.Net.Dns]::GetHostEntry("kube-dns.kube-system.svc.cluster.local")
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
        [string[]]$UrlCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$ExpectedContentCollection
    )

    Write-Host "Testing if service issue is present."

    $resultsArray = @()
    $serviceIsOk = $False
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
        $script:logs += $_.Exception.Response.StatusCode.Value__
    }
    return $serviceIsOk    
}

function Test-Port-Is-Opened {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$ServicesCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$PortsCollection
    )

    Write-Host "Testing if port issue is present."

    $resultsArray = @()
    $portIsOk = $False
    try {
        for ($i = 0; $i -lt $PortsCollection.Length; $i++) {
            $portStatus = nc -z -v -w5 $ServicesCollection[$i] $PortsCollection[$i] 2>&1

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
        $script:logs += $_.ScriptStackTrace
    }
    return $portIsOk
}

function Test-Domain-Address-Is-Resolved {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$ServicesCollection
    )

    Write-Host "Testing if domain issue is present."
    $resultsArray = @()
    [ref]$ValidIP = [ipaddress]::None
    $serviceDNSValue = "Address"
    $domainIsOk = $False
    try {
        for ($i = 0; $i -lt $ServicesCollection.Length; $i++) {
            $dnsCollection = nslookup $ServicesCollection[$i]

            ForEach ($dns in (1..($dnsCollection.Count - 1))) {
                if ($dnsCollection[$dns - 1].Contains($ServicesCollection[$i]) -And $dnsCollection[$dns].Contains($serviceDNSValue)) {
                    $script:ipAddresses += $dnsCollection[$dns].Split(":")[1].Trim()
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
        $script:logs += $_.ScriptStackTrace
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
    $addressIsOk = $False
    try {
        Write-Host "Testing if Address issue is present."

        for ($i = 0; $i -lt $PortsCollection.Length; $i++) {
            $address = $ProtocolsCollection[$i] + $ipAddresses[$i] + ":" + $PortsCollection[$i]
            Write-Host "Output! Service Address is: $address"
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
        $script:logs += $_.ScriptStackTrace
    }
    return $addressIsOk
}

$results = @();
$logs = @();
$ipAddresses = @();
$parsedUrlCollection = Get-Parsed-Url -UrlCollection $endpoints.Url -ExpectedContentCollection $endpoints.ExpectedContent

$IsSelfDnsOk = Test-Self-Check-DNS 
Write-Host "DNS is OK: $IsSelfDnsOk"
$results += $IsSelfDnsOk

$isServiceOk = Test-Service-Responds-By-Domain-Url -UrlCollection $parsedUrlCollection.AbsoluteUri -ExpectedContentCollection $parsedUrlCollection.ExpectedContent
Write-Host "Endpoints are OK: $isServiceOk"
$results += $isServiceOk

$isPortOk = Test-Port-Is-Opened -ServicesCollection $parsedUrlCollection.DnsSafeHost -PortsCollection $parsedUrlCollection.Port
Write-Host "Ports are OK: $isPortOk"
$results += $isPortOk

$isDomainOk = Test-Domain-Address-Is-Resolved -ServicesCollection $parsedUrlCollection.DnsSafeHost
Write-Host "Domains are OK: $isDomainOk"
$results += $isDomainOk

$isAddressOk = Test-Service-Responds-As-Expected-By-IP -ProtocolsCollection $parsedUrlCollection.Protocol -PortsCollection $parsedUrlCollection.Port -ExpectedContentCollection $parsedUrlCollection.ExpectedContent
Write-Host "IP addresses are OK: $isAddressOk"
$results += $isAddressOk

$finalResult = Get-Final-Result($results)
Show-Logs($logs)
Exit-Program($finalResult)