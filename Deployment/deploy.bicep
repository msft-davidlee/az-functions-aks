param prefix string
param appEnvironment string
param branch string
param location string
param subnetId string
param clientId string
@secure()
param clientSecret string
param managedUserId string
param scriptVersion string = utcNow()
param kubernetesVersion string = '1.21.2'
param version string

var stackName = '${prefix}${appEnvironment}'
var tags = {
  'stack-name': stackName
  'stack-environment': appEnvironment
  'stack-branch': branch
  'stack-version': version
}

resource wks 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: stackName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2021-05-01' = {
  name: stackName
  location: location
  tags: tags
  properties: {
    dnsPrefix: prefix
    kubernetesVersion: kubernetesVersion
    networkProfile: {
      networkPlugin: 'kubenet'
      serviceCidr: '10.250.0.0/16'
      dnsServiceIP: '10.250.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        osDiskSizeGB: 60
        count: 1
        minCount: 1
        maxCount: 6
        enableAutoScaling: true
        vmSize: 'Standard_B2ms'
        osType: 'Linux'
        osDiskType: 'Managed'
        vnetSubnetID: subnetId
        tags: tags
      }
    ]
    servicePrincipalProfile: {
      clientId: clientId
      secret: clientSecret
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: wks.id
        }
      }
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: stackName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    anonymousPullEnabled: false
    policies: {
      retentionPolicy: {
        days: 3
      }
    }
  }
}

resource customscript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: stackName
  kind: 'AzurePowerShell'
  location: location
  tags: tags
  dependsOn: [
    acr
    aks
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${managedUserId}': {}
    }
  }
  properties: {
    forceUpdateTag: scriptVersion
    azPowerShellVersion: '6.0'
    retentionInterval: 'P1D'
    arguments: '-aksName ${prefix} -rgName ${resourceGroup().name} -acrName ${acr.name}'
    scriptContent: loadTextContent('configureAKS.ps1')
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: stackName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: subnetId
          action: 'Allow'
        }
      ]
    }
  }
  tags: tags
}

resource tableSvcInStorageAccount 'Microsoft.Storage/storageAccounts/tableServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource tableInStorageAccount 'Microsoft.Storage/storageAccounts/tableServices/tables@2021-04-01' = {
  parent: tableSvcInStorageAccount
  name: 'TodoItem'
}

output acrName string = acr.name
output aksName string = aks.name
output storageConnection string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
