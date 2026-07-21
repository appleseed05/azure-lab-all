# Goal  
With this repo, you will deploy a lab environment in MS Azure with several Linux VM and F5 Distributed Cloud (XC) Customer Edge (CE).  

# Content  
This Terraform project will deploy multiple components in MS Azure.  
It includes the following :  
- Azure VNET with subnets and NAT Gateway  
- Azure VM Ubuntu server  
- Azure VM Ubuntu jumphost  
- F5 XC SMSv2 site with CE  
- F5 XC Virtual Site grouping the CE site  


# Requirement:
The script in this repo needs to be run on a machine with following software installed:  
* Git
* Terraform  
* Azure subscription (subscription ID and tenant ID)  
* F5 XC tenant  

And environment variable defined on you Operating System:
* **VES_P12_PASSWORD** for XC API certificate  

### Azure authentication:  
Azure Service Principal is the best option. Terraform provider script in this repo includes line for Client ID and Client Secret to use Service Principal.  
If you don't have Azure Service Principal, you can use interactive authentication with Azure CLI by running ```az login``` command. This command needs to be run on the machine executing Terraform. This requires to have Azure CLI installed.  

### F5 XC authentication:  
F5 XC auth offer API certificate or API token.  
XC Customer Edge deployment requires API certificate.  
This certificate needs to be **generated before** and copied in the same folder as TF files.  
Certificate password must be configured through OS environnement variable ```VES_P12_PASSWORD```.  

### F5 XC label:  
Virtual Site, used in this deployement, requires Labels.  
If the label you plan to use already exist in your current XC configuration, please set the value of ```f5xc_manage-labels``` to **false** in terraform.tfvars. Value is set to true in the provided file, assuming that the Label does not existe and will be created by Terraform.

# How to deploy  
1/ Git clone the repo on a machine meeting the requirements.  
2/ Go in the terraform folder of the project.  
3/ Rename **terraform.tfvars.expl** into **terraform.tfvars**.  
4/ Edit **terraform.tfvars** to define relevant value of all variables*. See bellow for variable that needs to be edited.  
5/ Execute Terraform deployment with command:  
```terraform init``` to initialize the project and download Terraform component (based on provider)  
```terraform plan``` to check the deployment  
```terraform apply```to launch the deployment if plan is successful  

*: Variables in **terraform.tfvars** must be reviewed before lauching deployment.  
Variables at the top of this files require to set a value. Others have a value already set, but it is highly recommanded to review and edit with suitable values for you.  
Please review the Warning section at the bottom of this page for XC object naming values.

Here are the variables that needs to be edited in terraform.tfvars:  
* azure_sub-id
* azure_tenant-id
* azure_client-id
* azure_client-secret
* azure_adminpassword
* allowed-pips
* f5xc_api-p12-file
* f5xc_namespace-name
* f5xc_vsite-name

Since all Terraform files are in the same folder, they will all be used to deploy the configuration when running terraform apply.  
Terraform deployment provide some output, including public IP provided by Azure.  

Execution of all the Terraform script can require up to 20 minutes to finish.  
After Terraform successful execution, you will find an RDP file in the current folder to connect to Jumphost machine.  
Please wait 15 or 20 minutes after Terraform execution finished for the Jumphost machine to be fully ready and reachable.  
XC CE installation and registration require around one hour to complete. If CE still to register after one hour and a half, then something is probably wrong. First thing to check is that you did not use any capital letter or special character in the object name.  

# How to use  
After successful deployment, you should connect to Jumphost VM using SSH or RDP.  
If connection does not work, please insure that you configure correctly the ```allowed-pips``` variable to define the public IP used by your machine.

Jumphost machine has access to all the others VM deployed in this Azure VNET.  

This Terraform project has been done and tested on Ubuntu Linux machine.  
It should also work on Windows with some adaptation, like the path of the certificate in variables to match Windows syntaxe (\ instead of /).  

A lot of security shortcut are used in this project. It is for lab purpose only, not for production!  
Same for Terraform code, it works but not state of the art.  

# WARNING:
For Azure VM, username must be the same username for admin username and ssh username.  

XC object name can ONLY use lower case alphanumeric caracters and dash. Must start by alphanumeric.  
If you don't follow those guideline, deployment will fail in best case. Worth case, Terraform deployment will succeded but XC configuration will not fully apply. For instance, CE registration will not work, with error only visible locally on the CE.

XC CE needs site token. It is obfuscated in console with SMS v2, but still used under the hood. Type 1 of site token is used for SMS v2, but not documented.  

CE image version comes from Azure marketplace. It is hardcoded on TF and may change in the future.  

An F5 XC Virtual Site (defined in main-xcsmsv2.tf, alongside the site and its Known Label) groups the CE site by label. The two CE VMs share one site token, so they are two nodes of ONE Secure Mesh Site; the site carries the custom label ```vsite = f5xc_vsite-name``` and the Virtual Site selects it (site_type CUSTOMER_EDGE). The Virtual Site therefore has one member site. To add more members later, give other CE sites the same ```vsite``` label. The Virtual Site is created in the ```shared``` namespace by default (variable ```f5xc_vsite-namespace```) so it can be referenced by load balancers / policies in any namespace. 
