param([int]$Seconds = 60, [int]$Intensity = 5)

$report = @{
    items = @()
}
for ($x = 0; $x -lt $Intensity; $x++) { 
    # Start Parallel Jobs
    Start-Job -ScriptBlock {
        param($Seconds, $Report)        
        $current = Get-Date
        $total = 0
        $counter = 0
        while ($true) {
            
            $end = Get-Date
            $diff = New-TimeSpan -Start $current -End $end

            for ($i = 0; $i -lt 1000; $i++) {
                $total += (Measure-Command -Expression { Invoke-RestMethod -UseBasicParsing -Uri http://contosoapi.com/ping -Method Post; }).Milliseconds
                $counter += 1
            }

            if ($diff.Seconds -gt $Seconds) {
                break
            }
        }

        $avg = $total / $counter
        $Report.items += $avg

    } -ArgumentList @($Seconds, $report)
}

Get-Job
$report