# Disclaimer
The information contained in this README.md file and any accompanying materials (including, but not limited to, scripts, sample codes, etc.) are provided "AS-IS" and "WITH ALL FAULTS." Any estimated pricing information is provided solely for demonstration purposes and does not represent final pricing and Microsoft assumes no liability arising from your use of the information. Microsoft makes NO GUARANTEES OR WARRANTIES OF ANY KIND, WHETHER EXPRESSED OR IMPLIED, in providing this information, including any pricing information.

# Introduction
This project demonstrates the ability to run Azure Functions on AKS using KEDA which means having the ability to be decide on the type of VMs (potentially lower your cost compared to a Premium Plan) to leverage for running your serverless workloads inside your own VNET (which Consumption Plan does not do).

### Azure Function
The Azure Function itself is running in .NET 5, and is using the isolated process. For more information on the difference, see: https://docs.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide.

## Architecture
The following uses 

# Demo
Ensure you have successfully deploy this solution before running the demo.

1. Login to CloudShell and run the following command ``` az aks get-credentials --resource-group aks-dev --name dleems10dev ```
2. Run the following command to get the pods that are running: ``` kubectl get pods -n app ```
3. On your local machine, let's start running the load test. Be sure to run the command from the root of this git repo. ``` $report = .\Test\LoadTest.ps1 -Seconds 60 -Intensity 10 -TestApi todo;$report ```
4. To watch for running pods, run the following command ``` kubectl get pods -o=name --field-selector=status.phase=Running -n app --watch ```
5. To observe the HPA in action, run ``` kubectl describe hpa -n app ``` For a simple version, run ``` kubectl get hpa -n app ```

## Have an issue?
You are welcome to create an issue if you need help but please note that there is no timeline to answer or resolve any issues you have with the contents of this project. Use the contents of this project at your own risk!