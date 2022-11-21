param entlzprefix string
param location string
param deploymentid string = substring(uniqueString(utcNow()),0,6)
param vdssprefix string
param vdmsprefix string
param allowedAzurePrefixes array

// From Parameters File
param vmsize string
param disksku string
param sablob string

targetScope = 'subscription'

// Location Var
var location_nospaces = toLower(replace(location, ' ', ''))
var location_short_usnat = replace(location_nospaces, 'usnat', '')
var location_short_ussec = replace(location_short_usnat, 'ussec', '')
var location_short = substring(replace(location_short_ussec, 'usgov', ''),0,4)

// VNET Start
var privatesubnetname  = 'private'
var publicsubnetname  = 'public'
var fproxysubnetname  = 'fproxy'
var rproxysubnetname  = 'rproxy'
var mgtsubnetname = 'mgt'
var vdssvnetname = 'vnet-${entlzprefix}-${location}-vdss-01'
var vdssvnetrg = 'rg-connectivity-vdss-001'

resource connectivityrg 'Microsoft.Resources/resourceGroups@2021-04-01'={
  name: 'rg-connectivity-vdss-001'
  location: location
}

module connectivityDeployment 'connectivity.bicep' = {
  name: 'connectivityDeployment_${deploymentid}'
  scope: connectivityrg
  params: {
    entlzprefix: entlzprefix
    vdmsprefix: vdmsprefix
    vdssprefix: vdssprefix
    fproxysubnetname: fproxysubnetname
    rproxysubnetname: rproxysubnetname
    privatesubnetname: privatesubnetname
    publicsubnetname: publicsubnetname
    mgtsubnetname: mgtsubnetname
    vnetname: vdssvnetname
    allowedAzurePrefixes: allowedAzurePrefixes
  }
}
// VNET END

// VDSS Artifact Storage Start
var vdssstorsaname  = 'sa${entlzprefix}vdssstor${location_short}1'
var vdssstorsargname = 'rg-storage-vdss-001'

resource vdssstorsarg 'Microsoft.Resources/resourceGroups@2021-04-01'={
  name: vdssstorsargnamed
  location: location
}

module vdssstorsa 'sa.bicep' = {
  name: 'deploy-${vdssstorsaname}-${deploymentid}'
  scope: vdssstorsarg
  dependsOn: [
    connectivityDeployment
  ]
  params: {
    vdssvnetname: vdssvnetname
    privatesubnetname: privatesubnetname
    publicsubnetname: publicsubnetname
    fproxysubnetname: fproxysubnetname
    rproxysubnetname: rproxysubnetname
    saname: vdssstorsaname
    vdssvnetrg: vdssvnetrg 
    bypass: 'AzureServices'
  }
}

// VM Diag Storage Start
var diagsaname  = 'sa${entlzprefix}vdssdiag${location_short}1'
var diagsargname = 'rg-diag-vdss-001'

resource diagstoragerg 'Microsoft.Resources/resourceGroups@2021-04-01'={
  name: diagsargname
  location: location
}

module diagsa 'sa.bicep' ={
  name: 'deploy-diagsaname-${deploymentid}'
  scope:  diagstoragerg
  dependsOn: [
    connectivityDeployment
  ]
  params:{
    vdssvnetname: vdssvnetname
    privatesubnetname: privatesubnetname
    publicsubnetname: publicsubnetname
    fproxysubnetname: fproxysubnetname
    rproxysubnetname: rproxysubnetname
    saname: diagsaname    
    vdssvnetrg: vdssvnetrg
    bypass: 'AzureServices, Logging, Metrics'    
  }
}

// Palo Alto NVAs

var sacontainer = 'disk-images'
//var sablob='PA-VM-HPV-10.1.0-SPECIALIZED.vhd'
var elbpipname = 'elbpip-${entlzprefix}-${location}-vdss-01'

resource pafwrg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-pafw-vdss-001'
  location: location  
}

module pafw 'pafw.bicep' = {
  name: 'deploy-pafw-${deploymentid}'
  scope: pafwrg
  dependsOn:[
    connectivityDeployment
    diagsa 
    vdssstorsa  
  ]
  params:{
    location: location
    vdssprefix: vdssprefix
    vnetname: vdssvnetname
    vnetrgname: vdssvnetrg
    sourceuri: '${vdssstorsa.outputs.sablobendpoint}${sacontainer}/${sablob}'
    vdssstorsaid: vdssstorsa.outputs.id
    pacount: 2
    elbpipname: elbpipname
    vmsize: vmsize
    disksku: disksku
  }
}
