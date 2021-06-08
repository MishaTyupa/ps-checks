param(
    [Parameter(Mandatory = $False)]
    [System.String]$protocol,
    [Parameter(Mandatory = $False)]
    [System.String]$service,
    [Parameter(Mandatory = $False)]
    [System.String]$port,
    [Parameter(Mandatory = $False)]
    [System.String]$endpoint,
    [Parameter(Mandatory = $False)]
    [System.String]$expectedStatusCode,
    [Parameter(Mandatory = $False)]
    [System.String]$portExpectedResult
)

function Test-Self-Check-DNS {
    Write-Host "Testing if dns issue is present."
    $timerDns = [Diagnostics.Stopwatch]::StartNew();
    $dnsTimeoutInMinutes = 1
    $dnsIsOk = $False
    do {
        Start-Sleep -s 5
        try {
            [System.Net.Dns]::GetHostEntry("kube-dns.kube-system.svc.cluster.local")
            Write-Host "Dns is resolved!SUCCESS!"
        }
        catch {
            if ($timerDns.Elapsed.TotalMinutes -lt $dnsTimeoutInMinutes) {
                continue
            }
            Write-Host "Dns issue is present!FAILED!"
        }
        $dnsIsOk = $True
    }
    until ($dnsIsOk)
}
function Test-Service-Responds-As-Expected {
    Write-Host "Testing if service issue is present."

        try {
            $serviceStatusCode = Invoke-WebRequest -Uri $endpoint -Verbose -UseBasicParsing | Select-Object -Expand StatusCode
            Write-Host "Output! Response status code for service endpoint" $endpoint "is:" $serviceStatusCode
            if ($serviceStatusCode -eq $expectedStatusCode) {
                Write-Host "Service status check for service endpoint $endpoint SUCCESS!"
            }
        }
        catch {
            $_.Exception.Response.StatusCode.Value__
            Write-Host "Service status check for service $endpoint FAILED!"
        }    
}

function Test-Port-Is-Opened {
    Write-Host "Passed parameters for service and port are: $service $port"
    Write-Host "Testing if port issue is present."

    $portStatus = nc -z -v -w5 $service $port 2>&1

    Write-Host "Output! Port status is: $portStatus"
    $portMatch = $portStatus | Select-String $portExpectedResult
    if (![string]::IsNullOrEmpty($portMatch)) {
        Write-Host "Port $port is opened!SUCCESS!" 
    }
    else {
        Write-Host "Port $port is closed!FAILED! "
    }
}

function Test-Domain-Address-Is-Resolved {
    [ref]$ValidIP = [ipaddress]::None
    $serviceFullName = $service + ".default.svc.cluster.local"
    $serviceDNSValue = "Address"

    Write-Host "Testing if domain issue is present."

    $dnsCollection = busybox nslookup $serviceFullName

    ForEach ($dns in (1..($dnsCollection.Count - 1))) {
        if ($dnsCollection[$dns - 1].Contains($serviceFullName) -And $dnsCollection[$dns].Contains($serviceDNSValue)) {
            $script:ip = $dnsCollection[$dns].Split(":")[1].Trim()
        }
    }

    if (![string]::IsNullOrEmpty($ip) -And [ipaddress]::TryParse($ip, $ValidIP)) {
        Write-Host "Domain name is mapped to IP Address!Ip status is: $ip. SUCCESS!" 
    }
    else {
        Write-Host "Domain name is NOT mapped to IP Address!Ip status is: $ip or empty. FAILED!"
    }
}

function Test-Service-Responds-As-Expected-By-IP {
    $address = $protocol + $ip + ":" + $port
    $ipStatusCode = Invoke-WebRequest -Uri $address -Verbose -UseBasicParsing | Select-Object -Expand StatusCode
    Write-Host "Testing if service IP issue is present."

    Write-Host "Output! Response status code by IP $ip is:" $ipStatusCode

    if ($ipStatusCode -eq $expectedStatusCode) {
        Write-Host "Service responds as expected directly by ip for service $service. SUCCESS!"
        exit 0 
    }
    else {
        Write-Host "Service failed to respond as expected directly by ip for service $service. FAILED!"
        exit 1
    }
}

Test-Self-Check-DNS
Test-Service-Responds-As-Expected -Endpoint $endpoint -ExpectedStatusCode $expectedStatusCode
Test-Port-Is-Opened -Service $service -Port $port -PortExpectedResult $portExpectedResult
Test-Domain-Address-Is-Resolved -Service $service
Test-Service-Responds-As-Expected-By-IP -Protocol $protocol -Service $service -Port $port -ExpectedStatusCode $expectedStatusCode