param([int]$Seconds = 60, [int]$Intensity = 5, $TestApi, [switch]$Incremental)

$report = @{
    jobs              = @();
    outputs           = @();
    avgInMs           = 0;
    started           = Get-Date;
    ended             = $null;
    durationInSeconds = $null;
}

for ($x = 0; $x -lt $Intensity; $x++) {

    if ($Incremental) {
        Start-Sleep -Seconds 1
    }

    # Start Parallel Jobs
    $job = Start-Job -ScriptBlock {
        param($Seconds, $TestApi)
        
        $current = Get-Date
        $total = 0
        $counter = 0
        $url = "http://api.contoso.com"
        $success = 0;
        $failure = 0;
        while ($true) {
            
            $total += (Measure-Command -Expression { 

                    if ($TestApi -eq "todo") {
                        $description = (New-Guid).ToString().Replace("-", " ")
                        $body = @{ description = $description; }

                        try {
                            Invoke-RestMethod -UseBasicParsing -Uri ($url + "/todo") -Body ($body | ConvertTo-Json) -Method Post
                            $success += 1 
                        }
                        catch {
                            $failure += 1
                        }
                
                    }

                    if ($TestApi -eq "ping") {

                        try {
                            Invoke-RestMethod -UseBasicParsing -Uri ($url + "/ping") -Method Post
                            $success += 1
                        }
                        catch {
                            $failure += 1
                        }
                
                    }                                                                        
                }).TotalMilliseconds
            
            $counter += 1

            $end = Get-Date
            $diff = New-TimeSpan -Start $current -End $end
            if ($diff.TotalSeconds -gt $Seconds) {
                break
            }
        }

        $avg = $total / $counter
        Write-Host "$avg,$success,$failure"

    } -ArgumentList @($Seconds, $TestApi, $WaitInSeconds)
    
    $report.jobs += $job
}

While (Get-Job -State "Running") {    
    Start-Sleep 10
}

$total = 0
$totalNumberOfRequests = 0
$totalNumberOfRequestsThatFailed = 0
for ($x = 0; $x -lt $Intensity; $x++) { 
    $output = Receive-Job -Job $report.jobs[$x] 6>&1
    $output = $output.ToString().Split(',')
    
    $avg = [System.Convert]::ToDecimal($output[0].ToString())
    $success = [System.Convert]::ToInt32($output[1].ToString())
    $failure = [System.Convert]::ToInt32($output[2].ToString())

    $totalNumberOfRequests += ($success + $failure)
    $totalNumberOfRequestsThatFailed += $failure
    $report.outputs += @{ 
        avg     = $avg; 
        success = $success; 
        failure = $failure; 
        rate    = ($success / ($success + $failure)) * 100;
    }
    Remove-Job -Name $report.jobs[$x].Name
    $total += $avg
}

$report.ended = Get-Date;
$report.durationInSeconds = (New-TimeSpan -Start $report.started -End $report.ended).TotalSeconds
$report.avgInMs = $total / $Intensity
$report.totalNumberOfRequests = $totalNumberOfRequests
$report.failureRate = ($totalNumberOfRequestsThatFailed / $totalNumberOfRequests) * 100

return $report