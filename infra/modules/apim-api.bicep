// Reusable module: one API on an existing API Management instance, routed to
// one backend (typically a Container App from container-app-service).
// Extracted from the bff/core blocks in the CLX repo's APIM/main.bicep: a
// backend, an API with wildcard operations, and an API policy that routes to
// the backend, with optional JWT + caller enforcement. The APIM instance itself
// is a shared platform resource and is only referenced.

@description('APIM service name (existing)')
param apimName string

@description('Short service name. Drives the default API, path and backend names (e.g. bff -> bff-api, /bff, bff-backend).')
param name string

@description('API name in APIM')
param apiName string = '${name}-api'

@description('API display name')
param apiDisplayName string = '${name} API'

@description('API path (public APIM route prefix)')
param apiPath string = name

@description('Backend entity name in APIM')
param backendName string = '${name}-backend'

@description('Backend base URL (for example, https://<container-app-fqdn>)')
param backendUrl string

@description('Backend title')
param backendTitle string = '${name} Container App backend'

@description('Backend description')
param backendDescription string = '${name} backend managed by Bicep.'

@description('Create or update the API definition. false = the API already exists and only its operations and policy are managed.')
param manageApiDefinition bool = true

@description('Require an APIM subscription key for this API')
param subscriptionRequired bool = true

@description('Wildcard operations to expose. Defaults to all common methods on /*.')
param operations array = [
  {
    operationId: 'get-all'
    method: 'GET'
  }
  {
    operationId: 'post-all'
    method: 'POST'
  }
  {
    operationId: 'put-all'
    method: 'PUT'
  }
  {
    operationId: 'patch-all'
    method: 'PATCH'
  }
  {
    operationId: 'delete-all'
    method: 'DELETE'
  }
  {
    operationId: 'options-all'
    method: 'OPTIONS'
  }
]

@description('Validate an Entra ID JWT and allow only the given caller client ID')
param enableJwtValidation bool = false

@description('Tenant ID used in the OpenID configuration URL when enableJwtValidation=true')
param tenantId string = ''

@description('Expected token audience when enableJwtValidation=true')
param jwtAudience string = ''

@description('Caller client ID (appid/azp claim) allowed when enableJwtValidation=true')
param allowedCallerClientId string = ''

@description('Full policy XML that replaces the generated policy. Empty = generated policy.')
param customPolicyXml string = ''

resource apim 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apimName
}

resource backend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  name: backendName
  parent: apim
  properties: {
    url: backendUrl
    protocol: 'http'
    title: backendTitle
    description: backendDescription
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2022-08-01' = if (manageApiDefinition) {
  name: apiName
  parent: apim
  properties: {
    displayName: apiDisplayName
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: backendUrl
    subscriptionRequired: subscriptionRequired
  }
}

// Parent for operations and the policy in both modes; dependsOn api orders them
// after the API definition when it is managed here.
resource apiRef 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: apiName
  parent: apim
}

resource wildcardOperations 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = [for op in operations: {
  name: op.operationId
  parent: apiRef
  properties: {
    displayName: '${op.method} /*'
    method: op.method
    urlTemplate: '/*'
  }
  dependsOn: [
    api
  ]
}]

// concat() over interpolation keeps the policy XML readable line by line.
#disable-next-line prefer-interpolation
var jwtValidationPolicy = concat(
  '    <validate-jwt header-name="Authorization"\n',
  '                  failed-validation-httpcode="401"\n',
  '                  failed-validation-error-message="Unauthorized">\n',
  '      <openid-config url="', environment().authentication.loginEndpoint, tenantId, '/v2.0/.well-known/openid-configuration" />\n',
  '      <audiences>\n',
  '        <audience>', jwtAudience, '</audience>\n',
  '      </audiences>\n',
  '    </validate-jwt>\n',
  '    <choose>\n',
  '      <when condition="@((context.Principal != null) && context.Principal.Claims.Any(c => (c.Type == &quot;appid&quot; || c.Type == &quot;azp&quot;) && c.Value == &quot;', allowedCallerClientId, '&quot;))">\n',
  '        <base />\n',
  '      </when>\n',
  '      <otherwise>\n',
  '        <return-response>\n',
  '          <set-status code="403" reason="Forbidden" />\n',
  '          <set-body>@("Caller is not authorized.")</set-body>\n',
  '        </return-response>\n',
  '      </otherwise>\n',
  '    </choose>\n'
)

#disable-next-line prefer-interpolation
var generatedPolicy = concat(
  '<policies>\n',
  '  <inbound>\n',
  '    <base />\n',
  '    <set-backend-service backend-id="', backendName, '" />\n',
  enableJwtValidation ? jwtValidationPolicy : '',
  '  </inbound>\n',
  '  <backend>\n',
  '    <base />\n',
  '  </backend>\n',
  '  <outbound>\n',
  '    <base />\n',
  '  </outbound>\n',
  '  <on-error>\n',
  '    <base />\n',
  '  </on-error>\n',
  '</policies>'
)

// After the operations too: APIM rejects concurrent writes to one API, so a policy written
// alongside the operations of a new API can fail with PreconditionFailed.
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  name: 'policy'
  parent: apiRef
  properties: {
    format: 'rawxml'
    value: empty(customPolicyXml) ? generatedPolicy : customPolicyXml
  }
  dependsOn: [
    api
    backend
    wildcardOperations
  ]
}

output apiId string = apiRef.id
output apiPath string = apiPath
output backendId string = backend.id
