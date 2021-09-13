param($aksName, $acrName, $rgName)

Install-AzAksKubectl -Version latest -Force
Import-AzAksCredential -ResourceGroupName $rgName -Name $aksName -Force

# Associate ACR with AKS
Set-AzAksCluster -ResourceGroupName $rgName -Name $aksName -AcrNameToAttach $acrName