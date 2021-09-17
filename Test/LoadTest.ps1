param([int]$Seconds = 60, [int]$Intensity = 5, $TestApi)

$report = @{
    items = @()
}
for ($x = 0; $x -lt $Intensity; $x++) { 
    # Start Parallel Jobs
    Start-Job -ScriptBlock {
        param($Seconds, $Report, $TestApi)        
        
        $current = Get-Date
        $total = 0
        $counter = 0
        $url = "http://contosoapi.com"

        while ($true) {
            
            $end = Get-Date
            $diff = New-TimeSpan -Start $current -End $end

            for ($i = 0; $i -lt 1000; $i++) {
                $total += (Measure-Command -Expression { 

                        if ($TestApi -eq "todo") {
                            $description = (New-Guid).ToString().Replace("-", " ")
                            $body = @{ description = $description; }
    
                            Invoke-RestMethod -UseBasicParsing -Uri ($url + "/todo") -Body ($body | ConvertTo-Json) -Method Post
                        }

                        if ($TestApi -eq "ping") {
                            Invoke-RestMethod -UseBasicParsing -Uri ($url + "/ping") -Method Post;
                        }                                                                        
                    }).Milliseconds
                $counter += 1
            }

            if ($diff.Seconds -gt $Seconds) {
                break
            }
        }

        $avg = $total / $counter
        $Report.items += $avg

    } -ArgumentList @($Seconds, $report, $TestApi)
}

Get-Job
$report