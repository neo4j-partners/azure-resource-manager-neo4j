# Neo4j EE and CE on Azure

Neo4j Enterprise and Community editions can be easily deployed on Virtual Machines in Microsoft Azure by using the following Azure Marketplace listings:

* [Neo4j Enterprise Edition](https://marketplace.microsoft.com/en-us/product/neo4j.neo4j-ee)
* [Neo4j Community Edition](https://marketplace.microsoft.com/en-us/product/neo4j.neo4j-ce)

> Neo4j does not provide Azure Marketplace Virtual Machine Images with a pre-installed version of the product. The Neo4j Azure Marketplace listings use Azure Resource Manager (ARM) templates that deploy and configure Neo4j dynamically with a shell script.


## Neo4j ARM template

Azure Resource Manager (ARM) is a declarative Infrastructure as Code (IaC) language that is based on JSON and instructs Azure to deploy a set of cloud resources.

The Neo4j ARM template takes several parameters as inputs, deploys a set of cloud resources, and provides outputs that can be used to connect to a Neo4j DBMS.
The  ARM template always installs the latest available version.

The repository structure is as follows:

```
azure-resource-manager-neo4j/
├── ce/                               # Community edition template
│   └── scripts/
│   │   └── startup.sh                # Startup script for Neo4j
│   │
|   ├── deploy.sh                     # Deployment script for Neo4j
|   ├── mainTemplate.json             # Main configuration template
│   └── mainTemplateParameters.json
├── ee/                               # Enterprise edition template
│   └── scripts/
│   │   └── startup.sh                # Startup script for Neo4j
│   │
|   ├── deploy.sh                     # Deployment script for Neo4j
|   ├── mainTemplate.json             # Main configuration template
│   └── mainTemplateParameters.json
├── marketplace/
|   ├── logo.png                      # Logo for GCP Marketplace
|   ├── makeArchive.sh                # Script that updates the listings
|   └── README.md                     # Notes for Neo4j employees who want to update the listings
├── LICENSE                           # TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION
└── README.md                         # This readme
```

## Important considerations

The deployment of cloud resources incurs costs.
Refer to the [Azure pricing calculator](https://azure.microsoft.com/en-gb/pricing/calculator/) for more information.

## Deployment prerequisites

Before deploying Neo4j using the ARM template, ensure you have the following prerequisites in place:

* A resource group.
You can either use an empty resource group, or create a new one.

* An active Azure subscription.

## Licensing

Installing and starting Neo4j from the Azure marketplace constitutes an acceptance of the Neo4j license agreement.
When deploying Neo4j, users are required to confirm that they either have an enterprise license.

<!-- If you require the Enterprise version of Bloom, you need to provide a key issued by Neo4j as this is required during the installation.

To obtain a valid license for Bloom reach out to your Neo4j account representative or get in touch using the [contact form](https://neo4j.com/contact-us/). -->


## Deploy from Azure Marketplace

1. Visit the [Neo4j Enterprise listing on Azure Marketplace](https://marketplace.microsoft.com/en-us/product/neo4j.neo4j-ee).
2. Click **Get it now**.
3. Select your plan, e.g., `BYOL`.
4. Select your subscription and click **Create**.
5. Configure the deployment parameters.
6. Review and click **Create**.

## Use the template directly

Alternatively, you can deploy this template from the command line.

1. Make a clone of this repository:

    ```bash
    git clone https://github.com/neo4j-partners/azure-resource-manager-neo4j.git
    cd azure-resource-manager-neo4j
    ```

3. Open the directory of the edition you want to deploy, for example, Enterprise:

    ```bash
    cd ee
    ```

4. Take a look at [deploy.sh](deploy.sh).

5. If the settings there look good, run:

    ```
    ./deploy.sh <RESOURCE_GROUP_NAME>
    ```
When complete the template prints the URL to access Neo4j.

### Deployed cloud resources

The environment created by the ARM template consists of the following Azure resources:

* 1 Virtual Network, with a CIDR range (address space) of `10.0.0.0/8`.
** A single subnet with the following CIDR range:
*** `10.0.0.0/16`
** A network security group.
* A Virtual Machine Scale-Set (VMSS), which creates:
** 1, or between 3 and 10 Virtual Machine instances (Depending on whether a single instance or an autonomous cluster is selected).
* 1 Load Balancer.

### Template outputs

After the deployment finishes successfully, the ARM template provides the following output, which can be found in the **Outputs** section of the deployments page in the Azure console.

* `neo4jBrowserURL` - URL to access Neo4j Browser.

> At the end of the deployment process, Azure runs a validation. If the validation fails, it might be because you have chosen VMs that are too large and exceed your Azure quota.
> If the Neo4j Browser is not coming up, there is a good chance something is not right in your deployment. One thing to investigate is the waagent output on a VM.  You'll need to SSH into the VM.  The relevant directory is `/var/lib/waagent/custom-script/download/1/`.
> If that looks ok, you might also check the Neo4j log file at `/var/log/neo4j/neo4j.log` and the config at `/etc/neo4j/neo4j.conf`.

## Delete deployment and destroy resources

To delete your deployment run:

```bash
az group delete --yes --name <RESOURCE_GROUP_NAME>
```