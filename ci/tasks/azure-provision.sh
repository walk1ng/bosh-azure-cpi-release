#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_DEFAULT_GROUP_NAME:?}
: ${AZURE_ADDITIONAL_GROUP_NAME:?}
: ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS:?}
: ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS:?}
: ${AZURE_DEFAULT_GROUP_NAME_CENTOS:?}
: ${AZURE_ADDITIONAL_GROUP_NAME_CENTOS:?}
: ${AZURE_REGION_NAME:?}
: ${AZURE_REGION_SHORT_NAME:?}
: ${AZURE_STORAGE_ACCOUNT_NAME:?}
: ${AZURE_STORAGE_ACCOUNT_NAME_MANAGED_DISKS:?}
: ${AZURE_VNET_NAME_FOR_BATS:?}
: ${AZURE_VNET_NAME_FOR_LIFECYCLE:?}
: ${AZURE_BOSH_SUBNET_NAME:?}
: ${AZURE_BOSH_SECOND_SUBNET_NAME:?}
: ${AZURE_CF_SUBNET_NAME:?}
: ${AZURE_CF_SECOND_SUBNET_NAME:?}

azure login --environment ${AZURE_ENVIRONMENT} --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

set +e

resource_group_names="${AZURE_DEFAULT_GROUP_NAME} ${AZURE_ADDITIONAL_GROUP_NAME} ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS} ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS} ${AZURE_DEFAULT_GROUP_NAME_CENTOS} ${AZURE_ADDITIONAL_GROUP_NAME_CENTOS}"
for resource_group_name in ${resource_group_names}
do
  # Check if the resource group already exists
  echo "azure group list | grep ${resource_group_name}"
  azure group list | grep ${resource_group_name}
  
  if [ $? -eq 0 ]
  then
    echo "azure group delete ${resource_group_name}"
    azure group delete ${resource_group_name} --quiet
    echo "waiting for delete operation to finish..."
    # Wait for the completion of deleting the resource group
    azure group show ${resource_group_name}
    while [ $? -eq 0 ]
    do
      azure group show ${resource_group_name} > /dev/null 2>&1
      echo "..."
    done
  fi
done

set -e

# Create the virtual networks, subnets, and the security groups
resource_group_names="${AZURE_DEFAULT_GROUP_NAME} ${AZURE_ADDITIONAL_GROUP_NAME} ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS} ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS} ${AZURE_DEFAULT_GROUP_NAME_CENTOS} ${AZURE_ADDITIONAL_GROUP_NAME_CENTOS}"
for resource_group_name in ${resource_group_names}
do
  echo azure group create ${resource_group_name} ${AZURE_REGION_SHORT_NAME}
  azure group create ${resource_group_name} ${AZURE_REGION_SHORT_NAME}
  cat > network-parameters.json << EOF
  {
    "virtualNetworkNameForBats": {
      "value": "${AZURE_VNET_NAME_FOR_BATS}"
    },
    "virtualNetworkNameForLifecycle": {
      "value": "${AZURE_VNET_NAME_FOR_LIFECYCLE}"
    },
    "subnetNameForBosh": {
      "value": "${AZURE_BOSH_SUBNET_NAME}"
    },
    "secondSubnetNameForBosh": {
      "value": "${AZURE_BOSH_SECOND_SUBNET_NAME}"
    },
    "subnetNameForCloudFoundry": {
      "value": "${AZURE_CF_SUBNET_NAME}"
    },
    "secondSubnetNameForCloudFoundry": {
      "value": "${AZURE_CF_SECOND_SUBNET_NAME}"
    }
  }
EOF
  azure group deployment create ${resource_group_name} --template-file ./bosh-cpi-src/ci/assets/azure/network.json --parameters-file ./network-parameters.json
done

# Create the Public IPs
resource_group_names="${AZURE_DEFAULT_GROUP_NAME} ${AZURE_ADDITIONAL_GROUP_NAME} ${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS} ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS} ${AZURE_DEFAULT_GROUP_NAME_CENTOS} ${AZURE_ADDITIONAL_GROUP_NAME_CENTOS}"
for resource_group_name in ${resource_group_names}
do
  echo azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-cf-lifecycle --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-cf-lifecycle --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
done

resource_group_names="${AZURE_ADDITIONAL_GROUP_NAME} ${AZURE_ADDITIONAL_GROUP_NAME_MANAGED_DISKS} ${AZURE_ADDITIONAL_GROUP_NAME_CENTOS}"
for resource_group_name in ${resource_group_names}
do
  echo azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-bosh --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-bosh --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  echo azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-cf-bats --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
  azure network public-ip create --resource-group ${resource_group_name} --name AzureCPICI-cf-bats --location ${AZURE_REGION_SHORT_NAME} --allocation-method Static
done

# Setup the storage account
resource_group_name="${AZURE_DEFAULT_GROUP_NAME}"
storage_account_name="${AZURE_STORAGE_ACCOUNT_NAME}"
azure storage account create --location ${AZURE_REGION_SHORT_NAME} --sku-name LRS --kind Storage --resource-group ${resource_group_name} ${storage_account_name}
storage_account_key=$(azure storage account keys list ${storage_account_name} --resource-group ${resource_group_name} --json | jq '.[0].value' -r)
azure storage container create --account-name ${storage_account_name} --account-key ${storage_account_key} --container bosh
azure storage container create --account-name ${storage_account_name} --account-key ${storage_account_key} --permission blob --container stemcell

resource_group_name="${AZURE_DEFAULT_GROUP_NAME_MANAGED_DISKS}"
storage_account_name="${AZURE_STORAGE_ACCOUNT_NAME_MANAGED_DISKS}"
azure storage account create --location ${AZURE_REGION_SHORT_NAME} --sku-name LRS --kind Storage --resource-group ${resource_group_name} ${storage_account_name}
storage_account_key=$(azure storage account keys list ${storage_account_name} --resource-group ${resource_group_name} --json | jq '.[0].value' -r)
azure storage container create --account-name ${storage_account_name} --account-key ${storage_account_key} --permission blob --container stemcell
