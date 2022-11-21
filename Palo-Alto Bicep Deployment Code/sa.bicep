param saname string
param vdssvnetname string
param privatesubnetname string
param publicsubnetname string
param fproxysubnetname string
param rproxysubnetname string
param vdssvnetrg string
param bypass string = 'None'

targetScope='resourceGroup'

resource vdssvnet 'Microsoft.Network/virtualNetworks@2021-02-01' existing ={
  name: vdssvnetname
  scope: resourceGroup(vdssvnetrg)
}

resource privatesubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing ={
  name: privatesubnetname
  scope: resourceGroup(vdssvnetrg)
}

resource fproxysubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing ={
  name: fproxysubnetname
  scope: resourceGroup(vdssvnetrg)
}

resource rproxysubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing ={
  name: rproxysubnetname
  scope: resourceGroup(vdssvnetrg)
}

resource publicsubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing ={
  name: publicsubnetname
  scope: resourceGroup(vdssvnetrg)
}

resource sa 'Microsoft.Storage/storageAccounts@2021-04-01'={
  name: saname
  location: resourceGroup().location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties:{
    networkAcls: {
      bypass: bypass
      virtualNetworkRules: [
        {
          id: '${vdssvnet.id}/subnets/${privatesubnetname}'
          action: 'Allow'
        }        
        {
          id: '${vdssvnet.id}/subnets/${publicsubnetname}'
          action: 'Allow'
        }      
        {
          id: '${vdssvnet.id}/subnets/${fproxysubnetname}'
          action: 'Allow'
        }   
        {
          id: '${vdssvnet.id}/subnets/${rproxysubnetname}'
          action: 'Allow'
        }                   
      ]
      defaultAction: 'Deny'
    }
  }
}

output sablobendpoint string = sa.properties.primaryEndpoints.blob
output id string = sa.id

