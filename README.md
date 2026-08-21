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
The project in this repo needs to be run on a machine with following software installed:  
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
Virtual Site, used in this deployment, requires Labels.  
The key and value of this label is configured through Terraform variables. Please check that this label key does not exist in your XC tenant.

# How to deploy  
1/ Git clone the repo on a machine meeting the requirements.  
2/ Go in the terraform folder of the project.  
3/ Rename **terraform.tfvars.example** into **terraform.tfvars**.  
4/ Edit **terraform.tfvars** to define relevant value of all variables*. See bellow for variable that needs to be edited.  
5/ Execute Terraform deployment with command:  
```terraform init``` to initialize the project and download Terraform component (based on provider)  
```terraform plan``` to check the deployment  
```terraform apply```to launch the deployment if plan is successful  

*: Variables in **terraform.tfvars** must be reviewed before lauching deployment.  
Variables at the top of this files require to set a value. Others have a value already set, but it is highly recommanded to review and edit with suitable values for you.  
Please review the Warning section at the bottom of this page for XC object naming values.

Here are the variables that needs to be edited in terraform.tfvars:  
* prefix
* azure_sub_id
* azure_tenant_id
* azure_client_id
* azure_client_secret
* azure_adminpassword
* allowed_pips
* f5xc_api_p12_file
* f5xc_namespace_name
* f5xc_label_key
* f5xc_label_value

The prefix variable is used to prefix all the object name created.

Since all Terraform files are in the same folder, they will all be used to deploy the configuration when running terraform apply.  
Terraform deployment provide some output, including public IP provided by Azure.  

Execution of all the Terraform script usually requires around three minutes to complete.  
After Terraform successful execution, you will find an RDP file in the current folder to connect to Jumphost machine.  
Please wait at least 10 minutes (15 preferably) after Terraform execution finished for the Jumphost machine to be fully ready and reachable.  
XC CE installation and registration require around one hour to complete. If CE still to register after one hour and a half, then something is probably wrong. First thing to check is that you did not use any capital letter or special character in the object name.  

# How to use  
After successful deployment, you should connect to Jumphost VM using SSH and RDP.  
If connection does not work, please insure that you configure correctly the ```allowed-pips``` variable to define the public IP used by your machine.

Jumphost machine has access to all the others VM deployed in this Azure VNET.  

This Terraform project has been tested on Ubuntu Linux and Windows 11 machine.  
It should work also on MacOS machine.  

A lot of security shortcut are used in this project. It is for lab purpose only, not for production!  
Same for Terraform code, it works but not state of the art.  

# WARNING:
For Azure VM, username must be the same for admin username and ssh username.  

XC object name can ONLY use lower case alphanumeric characters and dash. Must start by alphanumeric.  
If you don't follow those guideline, deployment will fail in best case. Worth case, Terraform deployment will succeeded but XC configuration will not fully apply. For instance, CE registration will not work, with error only visible locally on the CE.

XC CE needs site token. It is obfuscated in console with SMS v2, but still used under the hood. Type 1 of site token is used for SMS v2, but not documented.  

The two CE VMs are in different Secure Mesh Site (aka SMS or site). They are grouped in a Virtual Site using the label for association at site level.
The Virtual Site is located in the ```Shared``` namespace. The sites are in the ```System``` namespace.  
Http load balancer and Origin pool are located in your individual namespace, define in Terraform variable.  
