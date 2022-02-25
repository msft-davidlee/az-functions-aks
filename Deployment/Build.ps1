param(
    [string]$NETWORKING_PREFIX, 
    [string]$APP_PATH,
    [string]$BUILD_ENV, 
    [string]$RESOURCE_GROUP, 
    [string]$PREFIX,
    [string]$GITHUB_REF,
    [string]$CLIENT_ID,
    [string]$CLIENT_SECRET,
    [string]$MANAGED_USER_ID,
    [string]$VERSION)

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
$subnets = (az network vnet subnet list -g $vnetRg --vnet-name $vnetName | ConvertFrom-Json)
if (!$subnets) {
    throw "Unable to find eligible Subnets from Virtual Network $vnetName!"
}          
$subnetId = ($subnets | Where-Object { $_.name -eq "aks" }).id
if (!$subnetId) {
    throw "Unable to find Subnet resource!"
}

az network vnet subnet update -g $vnetRg -n aks --vnet-name $vnetName --service-endpoints Microsoft.Storage

$platformRes = (az resource list --tag stack-name=platform --tag stack-environment=prod | ConvertFrom-Json)
if (!$platformRes) {
    throw "Unable to find eligible platform resources!"
}
if ($platformRes.Length -eq 0) {
    throw "Unable to find 'ANY' eligible platform resources!"
}

$acr = ($platformRes | Where-Object { $_.type -eq "Microsoft.ContainerRegistry/registries" })
if (!$acr) {
    throw "Unable to find eligible platform container registry!"
}
$acrName = $acr.Name

$location = "centralus"
$deployOutputText = (az deployment group create --name $deploymentName --resource-group $RESOURCE_GROUP --template-file Deployment/deploy.bicep --parameters `
        location=$location `
        prefix=$PREFIX `
        appEnvironment=$BUILD_ENV `
        branch=$GITHUB_REF `
        clientId=$CLIENT_ID `
        clientSecret=$CLIENT_SECRET `
        managedUserId=$MANAGED_USER_ID `
        subnetId=$subnetId `
        version=$VERSION `
        acrName=$acrName `
        kubernetesVersion=$K_VERSION)

$deployOutput = $deployOutputText | ConvertFrom-Json
$aksName = $deployOutput.properties.outputs.aksName.value
$storageConnection = $deployOutput.properties.outputs.storageConnection.value

# Install Kubernets CLI and Login to AKS
az aks install-cli
az aks get-credentials --resource-group $RESOURCE_GROUP --name $aksName

# Install Azure Function Core tools
npm i -g azure-functions-core-tools@3 --unsafe-perm true

$kedaNamespace = kubectl get namespace app

if (!$kedaNamespace) {
    # Create namespaces for keda and your app
    #kubectl create namespace keda
    kubectl create namespace app
    if ($LastExitCode -ne 0) {
        throw "An error has occured. Unable to create namespace."
    }    
}

# These are two ways to install KEDA. We are using the second one.
# https://docs.microsoft.com/en-us/azure/azure-functions/functions-core-tools-reference?tabs=v2#func-kubernetes-deploy
# https://github.com/kedacore/http-add-on/blob/main/docs/install.md#installing-keda

$nlist = kubectl get deployment --namespace app -o json | ConvertFrom-Json

if (!$nlist -or $nlist.items.Length -eq 0) {
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    
    # TODO: Enable when we are ready to try out KEDA native implementation
    #helm install ingress-nginx ingress-nginx/ingress-nginx -n app
    
    helm install keda kedacore/keda -n app    
    helm install ingress-nginx ingress-nginx/ingress-nginx --namespace app `
        --set controller.replicaCount=2 `
        --set controller.metrics.enabled=true `
        --set-string controller.podAnnotations."prometheus\.io/scrape"="true" `
        --set-string controller.podAnnotations."prometheus\.io/port"="10254"
    
    # TODO: Enable when we are ready to try out KEDA native implementation
    # Here, we are also install the http add on as described here: https://github.com/kedacore/http-add-on/blob/main/docs/install.md#install-via-helm-chart
    # helm install http-add-on kedacore/keda-add-ons-http -n app    
}
else {
    Write-Host "Skipped installing kedacore and http."
}

$imageName = "my-todo-api:1.0"
$deployment = Get-Content Deployment/deployment.yaml
$deployment = $deployment.Replace('"%IMAGE%"', "$acrName.azurecr.io/$imageName")
$deployment = $deployment.Replace('%AZURE_STORAGE_CONNECTION%', $storageConnection)

Set-Content -Path "deployment.tmp" -Value $deployment
kubectl apply -f "deployment.tmp" --namespace app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to converted apply deployment.yaml."
}

kubectl apply -f Deployment/service.yaml --namespace app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to apply service.yaml."
}

kubectl apply --kustomize Deployment/prometheus -n app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to apply prometheus directory."
}

kubectl apply -f Deployment/functionapp-ingress.yml -n app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to apply functionapp-ingress.yml."
}

kubectl apply -f Deployment/prom-ingress.yml -n app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to apply prom-ingress.yml."
}

kubectl apply -f Deployment/prometheus-scaledobject.yaml -n app
if ($LastExitCode -ne 0) {
    throw "An error has occured. Unable to apply prometheus-scaledobject.yaml."
}

# TODO: Enable when we are ready to try out KEDA native implementation
# kubectl apply -f Deployment/httpscaledobject.yaml --namespace app
# if ($LastExitCode -ne 0) {
#     throw "An error has occured. Unable to apply httpscaledobject.yaml."
# }

# TODO: Enable when we are ready to try out KEDA native implementation
# kubectl apply -f Deployment/ingress.yaml --namespace app
# if ($LastExitCode -ne 0) {
#     throw "An error has occured. Unable to apply ingress.yaml."
# }