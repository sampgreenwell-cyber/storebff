// Reusable module: one service's own user-assigned identity, with only the access that service needs:
// AcrPull on the registry and Key Vault Secrets User on each of its own secrets (not the whole vault).
// The CLX BFF/API get the same isolation from system-assigned identities granted by a person running
// deploy.ps1; here the deploying pipeline grants it, so the deployer needs Role Based Access Control
// Administrator limited to these two roles (see README).
//
// A user-assigned identity exists, with its grants, before the Container App is created, so the first
// image pull already has AcrPull (system-assigned identities only exist once the app does).

@description('Identity name, e.g. ditac-clx-id-orders-d01')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Container registry name the service pulls from')
param registryName string

@description('Resource group of the registry (QA pulls from the dev registry in CLX)')
param registryResourceGroup string = resourceGroup().name

@description('Key Vault in this resource group holding the service\'s secrets. Empty = no Key Vault access.')
param keyVaultName string = ''

@description('The secrets this service may read. Access is granted per secret, never on the whole vault.')
param keyVaultSecretNames array = []

@description('Tags for the identity')
param tags object = {}

var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

// The secrets must already exist (a deploy fails with NotFound otherwise, as a Key Vault reference would).
resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = [for secretName in keyVaultSecretNames: {
  parent: keyVault
  name: secretName
}]

resource secretGrants 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (secretName, i) in keyVaultSecretNames: {
  name: guid(secrets[i].id, identity.id, keyVaultSecretsUserRoleId)
  scope: secrets[i]
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: identity.properties.principalId
    // Set explicitly: a new identity may not have replicated yet, and the type skips that lookup.
    principalType: 'ServicePrincipal'
    description: 'Golden path: ${name} reads ${secretName}'
  }
}]

module acrPull 'acr-pull.bicep' = {
  name: '${name}-acr-pull'
  scope: resourceGroup(registryResourceGroup)
  params: {
    registryName: registryName
    principalId: identity.properties.principalId
    identityId: identity.id
  }
}

output id string = identity.id
output name string = identity.name
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
