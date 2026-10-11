// Part of service-identity: AcrPull on one registry, deployed into the registry's resource group.

@description('Container registry name')
param registryName string

@description('Principal (object) ID of the identity')
param principalId string

@description('Resource ID of the identity (makes the assignment name stable per identity)')
param identityId string

var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identityId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Golden path: ${last(split(identityId, '/'))} pulls images'
  }
}
