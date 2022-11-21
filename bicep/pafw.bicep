param location string = resourceGroup().location
param pacount int = 2
param sourceuri string
param vdssstorsaid string
param vnetname string
param vnetrgname string
param vdssprefix string
param elbpipname string
param ilbip string = '${vdssprefix}.142'
param nsgsecurityrules array = [
  {
    name: 'Allow All'
    properties:{
      access: 'Allow'
      description: 'Allow All'                    
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
      direction: 'Inbound'
      priority: 500
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'

    }
  }
]
param vmsize string
param disksku string

targetScope='resourceGroup'

var vmnameprefix = 'pafw-0'
var avsetname = 'pafw-avset'
var pubnicname = 'pub'
var privnicname = 'priv'
var mgtnicname = 'mgt'

var osType = 'Linux'
var pubsubnetname = 'public'
var privsubnetname = 'private'
var mgtsubnetname = 'mgt'
var faultDomains = 2
var updateDomains = 3
var ilbname = 'pafw-private-ilb'
var lbrulename = 'pafw-private-ilb-default-rule'
var lbprobename = 'pafw-private-ilb-default-probe'
var lbfrontendipconfigurationname = 'pafw-private-loadBalancerFrontEnd'
var lbbackendaddresspoolname = 'pafw-private-loadBalancerBackEnd'

var elbskuname = 'Standard'
var elbpipskuname = 'Standard'
var elbname = 'pafw-public-elb'
var elbrulename = 'pafw-public-elb-default-rule'
var elbprobename = 'pafw-public-elb-default-probe'
var elbfrontendipconfigurationname = 'pafw-public-loadBalancerFrontEnd'
var elbbackendaddresspoolname = 'pafw-public-loadBalancerBackEnd'
var elboutboundrulename = 'pafw-public-outboundrule'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' existing = {
  name: vnetname
  scope: resourceGroup(vnetrgname)
}

resource pubsubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  name: pubsubnetname
  parent: vnet
}

resource privsubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  name: privsubnetname
  parent: vnet
}

resource mgtsubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  name: mgtsubnetname
  parent: vnet
}


// Firewall Network Virtual Appliances
resource avset 'Microsoft.Compute/availabilitySets@2021-04-01' = {
  name: avsetname
  location: location
  sku: {
    name: 'aligned'
  }
  properties: {
    platformFaultDomainCount: faultDomains
    platformUpdateDomainCount: updateDomains    
    
  }

}

resource pubnic 'Microsoft.Network/networkInterfaces@2021-02-01' = [for i in range(1,pacount): {
  name: '${vmnameprefix}${i}-nic-${pubnicname}'
  location: location
  dependsOn: [
    elb
  ]
  properties: {
    enableIPForwarding: true
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: '${pubnicname}-ipconfig'      
        properties: {
          primary: true
          subnet: {
            id: pubsubnet.id
          }      
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', elbname, elbbackendaddresspoolname)
            }
          ]    
        }
      }
    ]
  }
}]

resource privnic 'Microsoft.Network/networkInterfaces@2021-02-01' = [for i in range(1,pacount): {
  name: '${vmnameprefix}${i}-nic-${privnicname}'
  location: location
  dependsOn: [
    ilb
  ]
  properties: {
    enableIPForwarding: true
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: '${privnicname}-ipconfig'
        properties: {
          primary: true
          subnet: {
            id: privsubnet.id
          }          
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', ilbname, lbbackendaddresspoolname)
            }
          ]
        }
      }
    ]
  }
}]

resource mgtnic 'Microsoft.Network/networkInterfaces@2021-02-01' = [for i in range(1,pacount): {
  name: '${vmnameprefix}${i}-nic-${mgtnicname}'
  location: location
  properties: {  
    enableIPForwarding: true
    enableAcceleratedNetworking: true  
    ipConfigurations: [
      {
        name: '${mgtnicname}-ipconfig'
        properties: {
          primary: true
          subnet: {
            id: mgtsubnet.id
          }          
        }
      }
    ]
  }
}]

//Firewall disk and compute resources

resource disk 'Microsoft.Compute/disks@2020-12-01' = [for i in range(1,pacount): {
  name: 'osdisk-${vmnameprefix}${i}'
  location: location  
  sku: {
    name: disksku    
  }
  properties:  {     
   creationData: {
      createOption: 'Import'
      storageAccountId: vdssstorsaid
      sourceUri: sourceuri 
    }
    osType: osType
  }
}]

resource vm 'Microsoft.Compute/virtualMachines@2021-04-01'=[for i in range(1,pacount): {
  name: '${vmnameprefix}${i}'
  location: location  
  properties: {
    hardwareProfile: {
      vmSize: vmsize
    }
    availabilitySet: {
      id: avset.id
    }
    storageProfile: {
      osDisk: {
        osType: osType
        createOption: 'Attach'
        managedDisk: {
        id: disk[i-1].id
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: pubnic[i-1].id
          properties: {
            primary: false
          }
        }
        {
          id: privnic[i-1].id
          properties: {
            primary: false
          }
        }
        {
          id: mgtnic[i-1].id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true        
      }
    }
  }
}]

// Internal Load Balancer on Private Subnet
resource ilb 'Microsoft.Network/loadBalancers@2021-02-01' = {
  name: ilbname
  location: location
  sku: {
    name: 'Standard'    
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: lbfrontendipconfigurationname
        properties: {
          subnet: {
            id: privsubnet.id
          }
          privateIPAddress: ilbip
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
    backendAddressPools: [
      {
        name: lbbackendaddresspoolname        
      }
    ]
    loadBalancingRules: [
      {
        name: lbrulename
        properties: {
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools',ilbname, lbbackendaddresspoolname)
          }          
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations',ilbname,lbfrontendipconfigurationname)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes',ilbname, lbprobename)
          }
          frontendPort:  0
          protocol: 'All'
          backendPort: 0
          enableFloatingIP: false
          enableTcpReset: true
          loadDistribution: 'Default'
          disableOutboundSnat: true
          idleTimeoutInMinutes: 15
        }        
      }
    ]
    probes: [
      {
        name: lbprobename
        properties: {
          port: 80
          protocol: 'Tcp'
          intervalInSeconds: 15
          numberOfProbes: 2
        }

      }
    ]
  }  
}


// External Load Balancer on Public Subnet with Public IP Address
resource elbpip 'Microsoft.Network/publicIPAddresses@2021-05-01'={
  name: elbpipname
  location: location
  sku: {
    name: elbpipskuname
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource elb 'Microsoft.Network/loadBalancers@2021-02-01' = {
  name: elbname
  location: location
  sku: {
    name: elbskuname    
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: elbfrontendipconfigurationname
        properties: {
          publicIPAddress: {
            id: elbpip.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: elbbackendaddresspoolname        
      }
    ]
    loadBalancingRules: [
      {
        name: elbrulename
        properties: {
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools',elbname, elbbackendaddresspoolname)
          }          
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations',elbname,elbfrontendipconfigurationname)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes',elbname, elbprobename)
          }
          frontendPort:  443
          protocol: 'Tcp'
          backendPort: 443
          enableFloatingIP: false
          enableTcpReset: true
          loadDistribution: 'Default'
          disableOutboundSnat: true
          idleTimeoutInMinutes: 15
        }        
      }
    ]
    probes: [
      {
        name: elbprobename
        properties: {
          port: 443
          protocol: 'Tcp'
          intervalInSeconds: 15
          numberOfProbes: 2
        }

      }
    ]

    outboundRules: [
      {
          name: elboutboundrulename
          properties: {
              allocatedOutboundPorts: 0
              protocol: 'Tcp'
              enableTcpReset: false
              idleTimeoutInMinutes: 4
              backendAddressPool: {
                  id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools',elbname, elbbackendaddresspoolname)
              }
              frontendIPConfigurations: [
                  {
                      id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations',elbname,elbfrontendipconfigurationname)
                  }
              ]
          }
      }
  ]


  }  
}
