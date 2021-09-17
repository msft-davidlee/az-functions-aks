param([int]$Seconds = 60, [int]$Intensity = 5)

for ($x = 0; $x -lt $Intensity; $x++) { 
    # Start Parallel Jobs
    Start-Job -ScriptBlock {
        param($Seconds)        
        $current = Get-Date
        while ($true) {
            
            $end = Get-Date
            $diff = New-TimeSpan -Start $current -End $end

            for ($i = 0; $i -lt 1000; $i++) {
                Invoke-RestMethod -UseBasicParsing -Uri http://contosoapi.com/ping -Method Post; 
            }

            if ($diff.Seconds -gt $Seconds) {
                break
            }
        }

    } -ArgumentList $Seconds
}