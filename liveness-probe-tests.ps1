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

function Test-Self-Check-DNS {
    Write-Host "Testing if dns issue is present."
    $dnsIsOk = $False
    
    try {
        [System.Net.Dns]::GetHostEntry("kube-dns.kube-system.svc.cluster.local")
        $dnsIsOk = $True
    }
    catch {
        Write-Host $_.ScriptStackTrace
    }
    return $dnsIsOk
}

function Test-Service-Responds-By-Domain-Url {
    param(
        [Parameter(Mandatory = $True)]
        [string[]]$parsedUrlCollection,
        [Parameter(Mandatory = $True)]
        [string[]]$ExpectedContentCollection
    )

    Write-Host "Testing if service issue is present."
    $serviceIsOk = $False
    $resultsArray = @()
    try {
        for ($i = 0; $i -lt $parsedUrlCollection.Length; $i++) {
            $serviceStatus = Invoke-WebRequest -Uri $parsedUrlCollection[$i] -Verbose -UseBasicParsing 
            $serviceStatusCode = $serviceStatus | Select-Object -Expand StatusCode
            $serviceMatch = $serviceStatus.Content | Select-String -Pattern $ExpectedContentCollection[$i] | Select-Object -ExpandProperty Matches -First 1
            if ($serviceStatusCode -eq 200 -And $serviceMatch.Value -eq $ExpectedContentCollection[$i]) {
                $resultsArray += $True
            } else {
                $resultsArray += $False
            }
        }
        if (!($resultsArray -contains $False)) {
            $serviceIsOk = $True
        }
    }
    catch {
        $_.Exception.Response.StatusCode.Value__
    }
    return $serviceIsOk    
}

function Test-Port-Is-Opened {
    param(
        [Parameter(Mandatory = $True)]
        [string]$service,
        [Parameter(Mandatory = $True)]
        [string]$port
    )

    Write-Host "Passed parameters for service and port are: $service $port"
    Write-Host "Testing if port issue is present."
    $portIsOpened = $False

    $portStatus = nc -z -v -w5 $service $port 2>&1

    Write-Host "Output! Port status is: $portStatus"
    $portMatch = $portStatus | Select-String $portExpectedResult
    if (![string]::IsNullOrEmpty($portMatch)) {
        Write-Host "Port $port is opened!SUCCESS!"
        $portIsOpened = $True
    }
    return $portIsOpened
}

function Test-Domain-Address-Is-Resolved {
    param(
        [Parameter(Mandatory = $True)]
        [string]$service
    )

    Write-Host "Testing if domain issue is present."

    [ref]$ValidIP = [ipaddress]::None
    $serviceDNSValue = "Address"
    $domainIsResolved = $False
     
    $dnsCollection = busybox nslookup $service

    ForEach ($dns in (1..($dnsCollection.Count - 1))) {
        if ($dnsCollection[$dns - 1].Contains($service) -And $dnsCollection[$dns].Contains($serviceDNSValue)) {
            $script:ip = $dnsCollection[$dns].Split(":")[1].Trim()
        }
    }

    if (![string]::IsNullOrEmpty($ip) -And [ipaddress]::TryParse($ip, $ValidIP)) {
        Write-Host "Domain name is mapped to IP Address!Ip status is: $ip. SUCCESS!" 
        $domainIsResolved = $True
    }

    return $domainIsResolved
}

function Test-Service-Responds-As-Expected-By-IP {
    $serviceIsOk = $False
    $address = $protocol + $ip + ":" + $port
    $ipStatus = Invoke-WebRequest -Uri $address -Verbose -UseBasicParsing
    $ipStatusCode = $ipStatus | Select-Object -Expand StatusCode
    $ipMatch = $ipStatus | Select-String $expectedContent
    Write-Host "Testing if service IP issue is present."

    Write-Host "Output! Response status code by IP $ip is:" $ipStatusCode

    if ($ipStatusCode -eq $expectedStatusCode -And $ipMatch -eq $expectedContent) {
        Write-Host "Service responds as expected directly by ip for service $service. SUCCESS!"
        $serviceIsOk = $True
    }
    return $serviceIsOk
}

$results = @();
$parsedUrlCollection = Get-Parsed-Url -UrlCollection $endpoints.Url -ExpectedContentCollection $endpoints.ExpectedContent

#$IsSelfDnsOk = Test-Self-Check-DNS 
#Write-Host "DNS selfsheck: $IsSelfDnsOk"
#$results.Add($IsSelfDnsOk)

$isServiceRespondsByUrl = Test-Service-Responds-By-Domain-Url -ParsedUrlCollection $parsedUrlCollection.AbsoluteUri -ExpectedContentCollection $parsedUrlCollection.ExpectedContent
Write-Host "Endpoints check: $isServiceRespondsByUrl"
$results += $isServiceRespondsByUrl

#$finalResult = $results -Filter 
#$isServicePortOpened = Test-Port-Is-Opened -Service $parsedUrl.DnsSafeHost -Port $parsedUrl.Port
#Write-Host "Ports check: $isServicePortOpened"
#$results.Add($isPortOpened)

#$isServiceDomainResolved = Test-Domain-Address-Is-Resolved -Service $parsedUrl.DnsSafeHost
#Write-Host "Domains checks: $isServiceDomainResolved"
#$results.Add($isServiceDomainResolved)

#$isServiceRespondsDirectlyByIp = Test-Service-Responds-As-Expected-By-IP -Protocol $parsedUrl.Protocol -Service $parsedUrl.DnsSafeHost -Port $parsedUrl.Port
#Write-Host "IP addresses check: $isServiceRespondsDirectlyByIp"
#$results.Add($isServiceRespondsDirectlyByIp)

##### LOGS #####
#$logs