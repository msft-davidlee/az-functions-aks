# Disclaimer
The information contained in this README.md file and any accompanying materials (including, but not limited to, scripts, sample codes, etc.) are provided "AS-IS" and "WITH ALL FAULTS." Any estimated pricing information is provided solely for demonstration purposes and does not represent final pricing and Microsoft assumes no liability arising from your use of the information. Microsoft makes NO GUARANTEES OR WARRANTIES OF ANY KIND, WHETHER EXPRESSED OR IMPLIED, in providing this information, including any pricing information.

# Introduction
This project demonstrates the ability to run Azure Functions on AKS using KEDA which means having the ability to be decide on the type of VMs (potentially lower your cost compared to a Premium Plan) to leverage for running your serverless workloads inside your own VNET (which Consumption Plan does not do).

### Azure Function
The Azure Function itself is running in .NET 6, and is using the isolated process. For more information on the difference, see: https://docs.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide. Note that we are reusing the todo app from https://github.com/msft-davidlee/az-blazor-wasm which had been dockerized i.e. dockerfile was added. 

## Architecture

1. There are two levels of scaling, scaling the number of nodes, and scaling the number of pods. We have enabled cluster autoscaling on the AKS cluster which means scaling of the pods are taken care of by with a min and a max number of nodes value configured. The scaling of the pods are taken care of by the KEDA horizontal pod autoscaler. The values are defined in the yaml file in prometheus-scaledobject.yaml. The query is based on the number of HTTP requests and can be view on the Prometheus dashboard. For more information, see prometheus scaler for auto-scaling: https://keda.sh/docs/1.4/scalers/prometheus/. However, there is also a upcoming implementation from the KEDA team which makes it easier. For more information on that approach, see: https://github.com/kedacore/http-add-on
2. For a higher level of security, access to the Storage Account is restricted by Service endpoints confiugred on the Storage Account.
3. There is a Service Principal assigned to the AKS Cluster which has permissions to create the necessary resources in the Subscription. I am using this approach VS creating a managed identity because I can pre-assign the Service Principal with the right roles. A managed identity means I have to manually assign roles/permissions which does not help in automation.
4. The pods in the AKS cluster are running with their own networking i.e. kubenet VS Azure CNI. This means the Azure Functions are even isolated from the Azure network itself and external consumers outside cannot easily access them directly unless we have configured the ingress controller on the AKS cluster - which we did for the purpose of this demo. The Azure Function running inside the pod access the Storage Account via Storage service endpoints. Alternatively, we could have also used Private links to ensure traffic stays within the Azure network.

## More on scaling
A load test tool has been created that demonstrates the power of auto-scaling which speaks to how we can compare this approach with the consumption plan. See section on load test below.

# Get Started
To create this, please follow the steps below. 

1. Fork this git repo. See: https://docs.github.com/en/get-started/quickstart/fork-a-repo
2. Create two resource groups to represent two environments. Suffix each resource group name with either a -dev or -prod. An example could be todo-dev and todo-prod.
3. Next, you must create a service principal with Contributor roles assigned to the two resource groups.
4. In your github organization for your project, create two environments, and named them dev and prod respectively.
5. Create the following secrets in your github per environment. Be sure to populate with your desired values. The values below are all suggestions.
6. Note that the environment prefix of dev or prod will be appened to your resource group.

## Secrets
| Name | Comments |
| --- | --- |
| MS_AZURE_CREDENTIALS | <pre>{<br/>&nbsp;&nbsp;&nbsp;&nbsp;"clientId": "",<br/>&nbsp;&nbsp;&nbsp;&nbsp;"clientSecret": "", <br/>&nbsp;&nbsp;&nbsp;&nbsp;"subscriptionId": "",<br/>&nbsp;&nbsp;&nbsp;&nbsp;"tenantId": "" <br/>}</pre> |
| PREFIX | mytodos - or whatever name you would like for all your resources |
| CLIENT_ID | Serivce Principal Client Id running AKS cluster |
| CLIENT_SECRET | Serivce Principal Client Secret running AKS cluster  |
| RESOURCE_GROUP | resource group of this workload |
| MANAGED_USER_ID | user id you have assigned as a managed user identity in your resource group |
| NETWORKING_PREFIX | Used to discover which network you are creating your AKS cluster in |

# Demo
Ensure you have successfully deploy this solution before running the demo. 

1. Once the deployment is completed successfully, you need to figure out the public ip assigned. You can find out from the Portal by going to the cluster and viewing the Services and Ingress page.
2. Next you need to update your host file ``` C:\Windows\System32\drivers\etc\hosts ``` with the entry ``` <IP Address> api.contoso.com ```
3. Login to CloudShell and run the following command ``` az aks get-credentials --resource-group <Resource Group name> --name <Cluster Name> ``` - Be sure to change the resource group name and cluster name!
4. Run the following command to get the pods that are running: ``` kubectl get pods -n app ```
5. On your local machine, let's start running the load test. Be sure to run the command from the root of this git repo. ``` $report = .\Test\LoadTest.ps1 -Seconds 60 -Intensity 10 -TestApi todo;$report ```
6. To watch for running pods, run the following command ``` kubectl get pods -o=name --field-selector=status.phase=Running -n app --watch ```
7. To observe the HPA in action, run ``` kubectl describe hpa -n app ``` For a simple version, run ``` kubectl get hpa -n app ```
8. Now, you can start experimenting with running a few more load tests with varying intensity and time.
9. You can also review the insights view of your AKS cluster as well as Storage insights for how the "db" is handling your load. Azure Storage can scale really well and this shows the power of serverless.
10. When you click on the IP address itself, you will also be able to redirect to Prometheus to view the requests. Try the following command to see the load: ``` rate(nginx_ingress_controller_requests[1m]) ```
11. Lastly, because you have configured your local DNS via host file, you should be able to hit this endpoint and see your function running http://api.contoso.com

## About the Load Test
The load test will perform either a ping test or invoke a todo where an actual todo payload is created in the storage account. Please review following parameters:

| Name | Comments |
| --- | --- |
| Seconds | Number of seconds to run this load test |
| Intensity | Number of parallel jobs to spin up |
| TestApi | Either ping or todo |
| Incremental | A switch to add a 1 second delay before spinning up the next job |

## Ping Test
If you manually run a ping test, you can run the following commands.

```
$url="http://api.contoso.com"
Invoke-RestMethod -UseBasicParsing -Uri ($url + "/ping") -Method Post
```

You will get the following back as an example. This would be a good way to make sure you have configured this solution correctly.

```
Value Timestamp                    Server                       OS
----- ---------                    ------                       --
pong  2021-09-22T19:35:42.4705769Z httpfuncapp-69d545dc7b-gfl9w @{Platform=4; ServicePack=; Version=; VersionString=...
```

## Log Analytics Query
You can also use the following log analytics query to see the number of pods and nodes over a period of time.

```
KubePodInventory 
| where TimeGenerated > ago(60m)
| where PodStatus == "Running" and ServiceName == "httpfuncapp"
| summarize count() by bin(TimeGenerated, 1m)
| render columnchart

KubeNodeInventory
| where TimeGenerated > ago(60m)
| summarize count() by bin(TimeGenerated, 1m)
| render columnchart
```

## Have an issue?
You are welcome to create an issue if you need help but please note that there is no timeline to answer or resolve any issues you have with the contents of this project. Use the contents of this project at your own risk!