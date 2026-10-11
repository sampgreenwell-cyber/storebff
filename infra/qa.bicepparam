using './main.bicep'

// qa: the dev image, promoted after approval by the owning team.
param serviceName = 'store-bff'
param environmentName = 'qa'
param environmentCode = 'q01'
param location = 'East US'
param managedEnvironmentName = 'cae-platform-shared'
param acrLoginServer = 'samgplabacr.azurecr.io'
param imageRepository = 'lab/store-bff'
// Set by the pipeline. Locally: $env:IMAGE_TAG = '<tag>' before az deployment group what-if.
param imageTag = readEnvironmentVariable('IMAGE_TAG', '')
// The service gets its own identity (id-lab-store-bff-q01), granted AcrPull and read
// access to the secrets below only. The deploy identity needs Role Based Access Control Administrator
// limited to those two roles (platform-bicep-modules/service-identity/README.md).
// QA pulls from the dev registry.
param registryResourceGroup = 'rg-platform-services'
param keyVaultName = 'kv-samgp-lab'
param keyVaultSecretNames = [
  'dd-api-key'
]
param appSettings = []
param exposeViaApim = true
// Lab: dev and qa share one APIM, so qa publishes as <name>-qa-api on /<name>-qa.
param apimApiSuffix = '-qa'
param apimName = 'apim-samgp-lab'
// Caller check at APIM (off until the app registrations exist): when true, only an Entra ID token
// for jwtAudience issued to allowedCallerClientId (e.g. the BFF) gets through; 401/403 otherwise.
param requireCallerToken = false
param jwtAudience = ''
param allowedCallerClientId = ''
// The API this service calls (empty = none): an APIM subscription for this service, scoped to that API,
// becomes API_SUBSCRIPTION_KEY; API_BASE_URL is its APIM path unless downstreamApiBaseUrl is set.
param downstreamApiName = 'orders-api'
param downstreamApiBaseUrl = ''
param minReplicas = 1
param maxReplicas = 3
param ddEnv = 'lab-qa'
param ddTags = 'owner:guests,component:bff,service:store-bff'
param enableDatadogSidecar = false
param tags = {
  ApplicationCode: 'LAB'
  ApplicationName: 'LAB'
  Environment: 'QA'
  ManagedBy: 'backstage'
  SourceRepository: 'sampgreenwell-cyber/storebff'
}
