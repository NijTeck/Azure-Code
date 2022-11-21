param entlzprefix string
param vdssprefix string
param vdmsprefix string
param privatesubnetname string
param publicsubnetname string
param fproxysubnetname string
param rproxysubnetname string
param mgtsubnetname string
param vnetname string
param allowedAzurePrefixes array

targetScope = 'resourceGroup'

var location = resourceGroup().location

var azureRoutes = [for (prefix, i) in allowedAzurePrefixes: {
  name: 'AllowedAzurePrefix-${i}'
  properties: {
    addressPrefix: prefix
    nextHopType: 'Internet'
  }
}]


var defaultRoute = [
  {
    name: 'DefaultRoute'
    properties: {
      addressPrefix: '0.0.0.0/0'
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: fwip
    }
  }
]

var routes = concat(azureRoutes, defaultRoute)

var fwip = '${vdssprefix}.142'

var vdssvnetcidr  = [
  '${vdssprefix}.0/24'
]

var privatesubnetcidr  = '${vdssprefix}.128/28'
var publicsubnetcidr  = '${vdssprefix}.16/28'
var fproxysubnetcidr  = '${vdssprefix}.32/28'
var rproxysubnetcidr  = '${vdssprefix}.48/28'
var gwsubnetcidr  = '${vdssprefix}.64/26'
var mgtsubnetcidr = '${vdssprefix}.192/28'
var bastionsubnetcidr  = '${vdssprefix}.224/27'

var gwsubnetname  = 'GatewaySubnet'
var bastionsubnetname  = 'AzureBastionSubnet'

var vdssrtname = 'rt-${entlzprefix}-${location}-vdss-01'
var vdssgwrtname = 'rt-${entlzprefix}-${location}-vdssgw-01'

var dnsservers = [
  '${vdmsprefix}.4'
  '${vdmsprefix}.5'
  '<pip insert here>'
]

var bastionName = 'bastion-${entlzprefix}-${location}-01'
var bastionpipName = 'pip-bastion-${entlzprefix}-${location}-01'

var ergwname = 'ergw-${entlzprefix}-${location}-vdss-01'
var ergwpipname1 = 'ergwpip-${entlzprefix}-${location}-vdss-01'

resource vdssrt 'Microsoft.Network/routeTables@2021-02-01'={
  name: vdssrtname
  location: resourceGroup().location
  properties: {
    disableBgpRoutePropagation: true
    routes: routes
  }
}

resource vdssgwrt 'Microsoft.Network/routeTables@2021-02-01'={
  name: vdssgwrtname
  location: resourceGroup().location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'VDSS-Prefixes'
        properties: {
          addressPrefix: '${vdssprefix}.0/24'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: fwip        
        }
      }      
      {
        name: 'VDMS-Prefixes'
        properties: {
          addressPrefix: '${vdmsprefix}.0/24'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: fwip        
        }
      }      
    ]
  }
}

resource vnet 'Microsoft.Network/VirtualNetworks@2020-05-01' = {
  name: vnetname
  location: location
  tags: {}
  properties: {
    addressSpace: {
      addressPrefixes: vdssvnetcidr
    }
    dhcpOptions: {
      dnsServers: dnsservers
    }
    subnets: [
      {
        name: publicsubnetname
        properties: {
          addressPrefix: publicsubnetcidr          
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }        
      }
      {
        name: privatesubnetname
        properties: {
          addressPrefix: privatesubnetcidr   
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]       
        }
      }
      {
        name: fproxysubnetname
        properties: {
          addressPrefix: fproxysubnetcidr
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
          routeTable: {
            id: vdssrt.id
          }          
        }
      }
      {
        name: rproxysubnetname
        properties: {
          addressPrefix: rproxysubnetcidr
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
          routeTable: {
            id: vdssrt.id
          }
        }
      }
      {
        name: mgtsubnetname
        properties: {
          addressPrefix: mgtsubnetcidr
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
          routeTable: {
            id: vdssrt.id
          }
        }
      }
      {
        name: gwsubnetname
        properties: {
          addressPrefix: gwsubnetcidr          
          routeTable: {
            id: vdssgwrt.id
          }          
        }
      }            
      {
        name: bastionsubnetname
        properties: {
          addressPrefix: bastionsubnetcidr                                 
        }
      }
    ]    
  }
}

// ER Gateway
resource ergwpip1 'Microsoft.Network/publicIPAddresses@2021-02-01'={
  name: ergwpipname1
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'    
  }
}

resource gwsubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  name: gwsubnetname
  parent: vnet
}

resource ergw 'Microsoft.Network/virtualNetworkGateways@2021-02-01'={
  name: ergwname
  dependsOn: [
    ergwpip1
    vnet
  ]
  location: resourceGroup().location
  properties: {    
    ipConfigurations: [
      {
        properties: {          
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gwsubnet.id
          }
          publicIPAddress: {
            id: ergwpip1.id
          }          
        }
        name: 'gwIPconf1'        
      }      
    ]
    gatewayType: 'ExpressRoute'
    sku: {
      name: 'HighPerformance'
      tier: 'HighPerformance'
    }
    vpnType: 'RouteBased'
  }
}

// Bastion Service

resource bastionpip 'Microsoft.Network/publicIPAddresses@2021-02-01' ={
  name: bastionpipName
  sku: {
    name: 'Standard'
  }
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'    
  }
}

resource bastionsubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: vnet
  name: bastionsubnetname
}

resource bastion 'Microsoft.Network/bastionHosts@2021-02-01' = {
  name: bastionName  
  location: location  
  dependsOn: [
    vnet
    bastionpip
  ]
  properties:{
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {           
           publicIPAddress: {
             id: bastionpip.id
           }
           subnet: {
            id: bastionsubnet.id
           }
        }
      }
    ]
  }
}


output vnetid string = vnet.id
