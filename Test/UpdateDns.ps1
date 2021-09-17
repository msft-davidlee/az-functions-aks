param($OldIP, $NewIP)

$content = Get-Content C:\Windows\System32\drivers\etc\hosts
$content = $content.Replace($OldIP, $NewIP)
Set-Content -Path C:\Windows\System32\drivers\etc\hosts -Value $content
Get-Content C:\Windows\System32\drivers\etc\hosts