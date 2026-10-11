// Reusable module: one Container App service (BFF or API style) in an existing
// Container Apps managed environment. Extracted from the bffContainerApp /
// apiContainerApp blocks in WebApps/main.bicep so a new service needs only a
// module call plus a small parameter file. Shared platform resources (managed
// environment, ACR, Key Vault, APIM, Front Door) are referenced, never created.

@description('Container App name (lowercase alnum or hyphen, 2-32 chars, e.g. ditac-clx-ca-<svc>-d01)')
@minLength(2)
@maxLength(32)
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Resource ID of the existing Container Apps managed environment')
param managedEnvironmentId string

@description('Name of the application container inside the Container App (e.g. bff, api)')
param containerName string = 'app'

@description('Full image reference, e.g. ditacclxacrwid01.azurecr.io/vxc/bff:dev-20260511-212112-815924d')
param image string

@description('ACR login server the image is pulled from')
param registryServer string

@description('User-assigned managed identity resource ID used for ACR pull and Key Vault references. Empty = system-assigned identity.')
param userAssignedIdentityResourceId string = ''

@description('Application target port')
param targetPort int = 8080

@description('HTTP path used for startup, readiness and liveness probes')
param healthPath string = '/health'

@description('Expose the Container App using external ingress')
param externalIngress bool = true

@description('IPv4 CIDR allowlist for ingress (for example, APIM outbound /32 IPs)')
param ingressAllowCidrs array = []

@description('Minimum replicas')
param minReplicas int = 1

@description('Maximum replicas')
param maxReplicas int = 3

@description('CPU cores')
param cpu string = '0.5'

@description('Memory')
param memory string = '1Gi'

@description('Environment variables for the application container (name/value or name/secretRef)')
param env array = []

@description('Existing Key Vault name in the current resource group. Required when keyVaultSecretNames is set.')
param keyVaultName string = ''

@description('Key Vault secret names exposed as Container App secrets of the same name. Names must be lowercase alnum or hyphen.')
param keyVaultSecretNames array = []

@description('Additional raw secret definitions (name/value or name/keyVaultUrl/identity), appended after keyVaultSecretNames')
param additionalSecrets array = []

@description('Secret values computed at deploy time (e.g. an APIM subscription key read with listSecrets()), as {secret-name: value}. Secure, so the values stay out of deployment history; appended after additionalSecrets.')
@secure()
param secretValues object = {}

@description('Assign Key Vault Secrets User to the system-assigned identity. Ignored with a user-assigned identity, whose roles are pre-granted by the platform.')
param assignKeyVaultSecretsUserRole bool = false

@description('Tags for resources')
param tags object = {}

@description('Deploy a Datadog Agent sidecar (APM traces + DogStatsD) alongside the app container')
param enableDatadogSidecar bool = false

@description('Datadog Agent image for the sidecar')
param datadogAgentImage string = 'index.docker.io/datadog/agent:7'

@description('Datadog Agent sidecar CPU cores')
param datadogSidecarCpu string = '0.25'

@description('Datadog Agent sidecar memory')
param datadogSidecarMemory string = '0.5Gi'

@description('Datadog intake site. datadoghq.com = US1')
param ddSite string = 'datadoghq.com'

@description('Datadog environment tag for the sidecar (for example clx-stg). Empty = omit')
param ddEnv string = ''

@description('Name of the container-app secret holding the Datadog API key (must exist in the app secrets)')
param datadogApiKeySecretName string = 'dd-api-key'

var useUserAssignedIdentity = !empty(userAssignedIdentityResourceId)
var identityRef = useUserAssignedIdentity ? userAssignedIdentityResourceId : 'system'
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

var keyVaultSecrets = [for secretName in keyVaultSecretNames: {
  name: secretName
  keyVaultUrl: 'https://${toLower(keyVaultName)}${environment().suffixes.keyvaultDns}/secrets/${secretName}'
  identity: identityRef
}]

// Datadog Agent sidecar: shares the container-app network namespace with the app
// container, so the app's dd-java-agent reaches the trace-agent on 127.0.0.1:8126
// and DogStatsD on 127.0.0.1:8125 with no app-image change. Replaces the
// serverless-init PID-1 approach, which crash-loops on ACA (verified 2026-08-27).
// Requires a container-app secret named `datadogApiKeySecretName` (dd-api-key).
// DD_HOSTNAME set explicitly: ACA gives the agent no resolvable hostname, which otherwise fails startup.
var datadogSidecarContainer = {
  name: 'datadog-agent'
  image: datadogAgentImage
  resources: {
    cpu: json(datadogSidecarCpu)
    memory: datadogSidecarMemory
  }
  env: concat([
    {
      name: 'DD_API_KEY'
      secretRef: datadogApiKeySecretName
    }
    {
      name: 'DD_SITE'
      value: ddSite
    }
    {
      name: 'DD_APM_ENABLED'
      value: 'true'
    }
    {
      name: 'DD_APM_NON_LOCAL_TRAFFIC'
      value: 'true'
    }
    {
      name: 'DD_DOGSTATSD_NON_LOCAL_TRAFFIC'
      value: 'true'
    }
    {
      name: 'DD_BIND_HOST'
      value: '0.0.0.0'
    }
    {
      // Logs already ship via the in-app DatadogLogAppender; don't duplicate via the agent.
      name: 'DD_LOGS_ENABLED'
      value: 'false'
    }
    {
      name: 'DD_PROCESS_AGENT_ENABLED'
      value: 'false'
    }
    {
      // ACA exposes no Docker socket / host cgroups; skip container autodiscovery to avoid agent errors.
      name: 'DD_CONTAINER_EXCLUDE'
      value: 'name:.*'
    }
    {
      name: 'DD_LOG_LEVEL'
      value: 'warn'
    }
  ], empty(ddEnv) ? [] : [
    {
      name: 'DD_ENV'
      value: ddEnv
    }
  ], [
    {
      name: 'DD_HOSTNAME'
      value: name
    }
  ])
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: useUserAssignedIdentity
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${userAssignedIdentityResourceId}': {}
        }
      }
    : {
        type: 'SystemAssigned'
      }
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      ingress: {
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        ipSecurityRestrictions: [for (cidr, i) in ingressAllowCidrs: {
          name: 'apim-allow-${i + 1}'
          action: 'Allow'
          ipAddressRange: cidr
          description: 'Allow APIM egress'
        }]
      }
      activeRevisionsMode: 'Single'
      secrets: concat(keyVaultSecrets, additionalSecrets, map(items(secretValues), secret => {
        name: secret.key
        value: secret.value
      }))
      registries: [
        {
          server: registryServer
          identity: identityRef
        }
      ]
    }
    template: {
      containers: concat([
        {
          name: containerName
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: env
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: healthPath
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              failureThreshold: 24
            }
            {
              type: 'Readiness'
              httpGet: {
                path: healthPath
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              failureThreshold: 6
            }
            {
              type: 'Liveness'
              httpGet: {
                path: healthPath
                port: targetPort
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ], enableDatadogSidecar ? [datadogSidecarContainer] : [])
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!useUserAssignedIdentity && assignKeyVaultSecretsUserRole && !empty(keyVaultName)) {
  name: guid(keyVault.id, containerApp.id, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output systemAssignedPrincipalId string = useUserAssignedIdentity ? '' : containerApp.identity.principalId
