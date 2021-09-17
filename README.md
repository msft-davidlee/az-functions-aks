# Disclaimer
The information contained in this README.md file and any accompanying materials (including, but not limited to, scripts, sample codes, etc.) are provided "AS-IS" and "WITH ALL FAULTS." Any estimated pricing information is provided solely for demonstration purposes and does not represent final pricing and Microsoft assumes no liability arising from your use of the information. Microsoft makes NO GUARANTEES OR WARRANTIES OF ANY KIND, WHETHER EXPRESSED OR IMPLIED, in providing this information, including any pricing information.

# Introduction
This project demonstrates the ability to run Azure Functions on AKS using KEDA which means having the ability to be decide on the type of VMs (potentially lower your cost compared to a Premium Plan) to leverage for running your serverless workloads inside your own VNET (which Consumption Plan does not do).

### Azure Function
The Azure Function itself is running in .NET 5, and is using the isolated process. For more information on the difference, see: https://docs.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide.

## Architecture
The following is a link to the underlying infrastructure offered by KEDA HTTP-Add-On: https://github.com/kedacore/http-add-on/blob/main/docs/design.md#architecture-overview

## Have an issue?
You are welcome to create an issue if you need help but please note that there is no timeline to answer or resolve any issues you have with the contents of this project. Use the contents of this project at your own risk!