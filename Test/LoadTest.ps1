param([int]$Seconds = 60, [int]$Intensity = 5, $TestApi)

$report = @{
    jobs    = @();
    outputs = @();
    avgInMs     = 0;
}

for ($x = 0; $x -lt $Intensity; $x++) { 
    # Start Parallel Jobs
    $job = Start-Job -ScriptBlock {
        param($Seconds, $TestApi)        
        
        $current = Get-Date
        $total = 0
        $counter = 0
        $url = "http://contosoapi.com"

        while ($true) {
            
            $end = Get-Date
            $diff = New-TimeSpan -Start $current -End $end

            for ($i = 0; $i -lt 10; $i++) {
                $total += (Measure-Command -Expression { 

                        if ($TestApi -eq "todo") {
                            $description = (New-Guid).ToString().Replace("-", " ")
                            $body = @{ description = $description; }
    
                            Invoke-RestMethod -UseBasicParsing -Uri ($url + "/todo") -Body ($body | ConvertTo-Json) -Method Post
                        }

                        if ($TestApi -eq "ping") {
                            Invoke-RestMethod -UseBasicParsing -Uri ($url + "/ping") -Method Post
                        }                                                                        
                    }).Milliseconds
                $counter += 1
            }

            if ($diff.Seconds -gt $Seconds) {
                break
            }
        }

        $avg = $total / $counter
        Write-Host $avg

    } -ArgumentList @($Seconds, $TestApi)

    $report.jobs += $job
}

While (Get-Job -State "Running") {    
    Start-Sleep 10
}

$total = 0
for ($x = 0; $x -lt $Intensity; $x++) { 
    $avg = Receive-Job -Job $report.jobs[$x] 6>&1
    $report.outputs += $avg
    Remove-Job -Name $report.jobs[$x].Name
    $total += ([System.Convert]::ToDecimal($avg.ToString()))
}

$report.avgInMs = $total / $Intensity

return $report