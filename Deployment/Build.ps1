param(
    [string]$NETWORKING_PREFIX, 
    [string]$APP_PATH,
    [string]$BUILD_ENV, 
    [string]$RESOURCE_GROUP, 
    [string]$PREFIX,
    [string]$GITHUB_REF,
    [string]$CLIENT_ID,
    [string]$CLIENT_SECRET,
    [string]$MANAGED_USER_ID)

$ErrorActionPreference = "Stop"

$deploymentName = "aksdeploy" + (Get-Date).ToString("yyyyMMddHHmmss")
$platformRes = (az resource list --tag stack-name=$NETWORKING_PREFIX | ConvertFrom-Json)
if (!$platformRes) {
    throw "Unable to find eligible Virtual Network resource!"
}
if ($platformRes.Length -eq 0) {
    throw "Unable to find 'ANY' eligible Virtual Network resource!"
}
$vnet = ($platformRes | Where-Object { $_.type -eq "Microsoft.Network/virtualNetworks" -and $_.name.Contains("-pri-") -and $_.resourceGroup.EndsWith("-$BUILD_ENV") })
if (!$vnet) {
    throw "Unable to find Virtual Network resource!"
}
$vnetRg = $vnet.resourceGroup
$vnetName = $vnet.name
$location = $vnet.location
$subnets = (az network vnet subnet list -g $vnetRg --vnet-name $vnetName | ConvertFrom-Json)
if (!$subnets) {
    throw "Unable to find eligible Subnets from Virtual Network $vnetName!"
}          
$subnetId = ($subnets | Where-Object { $_.name -eq "aks" }).id
if (!$subnetId) {
    throw "Unable to find Subnet resource!"
}

$rgName = "$RESOURCE_GROUP-$BUILD_ENV"
$deployOutputText = (az deployment group create --name $deploymentName --resource-group $rgName --template-file Deployment/deploy.bicep --parameters `
        location=$location `
        prefix=$PREFIX `
        appEnvironment=$BUILD_ENV `
        branch=$GITHUB_REF `
        clientId=$CLIENT_ID `
        clientSecret=$CLIENT_SECRET `
        managedUserId=$MANAGED_USER_ID `
        subnetId=$subnetId `
        kubernetesVersion=$K_VERSION)

$deployOutput = $deployOutputText | ConvertFrom-Json
$acrName = $deployOutput.properties.outputs.acrName.value
$aksName = $deployOutput.properties.outputs.aksName.value
$storageConnection = $deployOutput.properties.outputs.storageConnection.value

# Install Kubernets CLI and Login to AKS
az aks install-cli
az aks get-credentials --resource-group $rgName --name $aksName

# Install Azure Function Core tools
npm i -g azure-functions-core-tools@3 --unsafe-perm true

# Create namespaces for keda and your app
$kedaNamespace = kubectl get namespace keda
if (!$kedaNamespace) {
    kubectl create namespace keda
    kubectl create namespace app
    if ($LastExitCode -ne 0) {
        throw "An error has occured. Unable to create namespace."
    }    
}

# These are two ways to install KEDA. We are using the second one.
# https://docs.microsoft.com/en-us/azure/azure-functions/functions-core-tools-reference?tabs=v2#func-kubernetes-deploy
# https://github.com/kedacore/http-add-on/blob/main/docs/install.md#installing-keda

$nlist = kubectl get deployment --namespace keda -o json | ConvertFrom-Json

if (!$nlist -or $nlist.items.Length -eq 0) {
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    helm install keda kedacore/keda --namespace keda
    # Here, we are also install the http add on as described here: https://github.com/kedacore/http-add-on/blob/main/docs/install.md#install-via-helm-chart
    helm install http-add-on kedacore/keda-add-ons-http --namespace keda
}

# Login to ACR
az acr login --name $acrName
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to login to acr."
}

$list = az acr repository list --name $acrName | ConvertFrom-Json
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to list from repository"
}

# Build your app with ACR build command
$imageName = "app:v1"
if (!$list -or !$list.Contains("app")) {
    Push-Location $APP_PATH
    az acr build --image $imageName -r $acrName --file ./MyTodo.Api/Dockerfile .
    
    if ($LastExitCode -ne 0) {
        throw "An error has occured. Unable to build image."
    }

    Pop-Location
}

$deployment = Get-Content Deployment/deployment.yaml
$deployment = $deployment.Replace('"%IMAGE%"', "$acrName.azurecr.io/$imageName")
$deployment = $deployment.Replace('%AZURE_STORAGE_CONNECTION%', $storageConnection)
$deployment = $deployment.Replace('"%AZURE_CLIENT_ID%"', "test")
$deployment = $deployment.Replace('"%AZURE_CLIENT_SECRET%"', "test")

$deployment

Set-Content -Path "deployment.tmp" -Value $deployment
kubectl apply -f "deployment.tmp" --namespace app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to run deployment.tmp."
}

kubectl apply -f Deployment/service.yaml --namespace app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to run service.yaml."
}

kubectl apply -f Deployment/httpscaledobject.yaml --namespace app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to run httpscaledobject.yaml."
}

# Push-Location $APP_PATH\MyTodo.Api

# $localSettings = @{
#     "IsEncrypted" = $false;
#     "Values"      = @(
#         @{"AzureWebJobsStorage" = "UseDevelopmentStorage=true"; };
#         @{"FUNCTIONS_WORKER_RUNTIME" = "dotnet-isolated"; };
#         @{"TableStorageConnection" = "UseDevelopmentStorage=true"; };
#         @{"AzureAd:ClientId" = ""; };
#         @{"AzureAd:Instance" = ""; };
#     );
#     "Host"        = @{
#         "CORS" = "*";
#     };
# }

# Set-Content -Path .\local.settings.json -Value $localSettings

# $yml = func kubernetes deploy --name appdeployment --registry "$acrName.azurecr.io" --namespace app --image-name $imageName --dry-run
# if ($LastExitCode -ne 0) {
#     throw "An error has occured. Unable to generate func yml."
# }

# $yml

# Set-Content -Path "temp.yml" -Value $yml
# kubectl apply -f "temp.yml" --namespace app