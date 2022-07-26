
@description('The location to deploy our application to. Default is location of resource group')
param location string = resourceGroup().location

@description('Name of our application.')
param applicationName string = uniqueString(resourceGroup().id)

@description('The image used for the Checkout app')
param checkoutImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('The image used for the Order Processor app')
param orderProcessorImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var containerRegistryName = '${applicationName}acr'
var logAnalyticsWorkspaceName = '${applicationName}law'
var appInsightsName = '${applicationName}ai'
var containerAppEnvironmentName = '${applicationName}env'
var serviceBusName = '${applicationName}sb'
var topicName = 'orders'
var checkoutApp = 'checkout'
var orderProcessorApp = 'order-processor'
var targetPort = 80

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: serviceBusName
  location: location
  sku: {
    name: 'Standard'
  }
  identity: {
   type: 'SystemAssigned' 
  }
}

resource ordersTopic 'Microsoft.ServiceBus/namespaces/topics@2022-01-01-preview' = {
  name: topicName
  parent: serviceBus
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    } 
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource environment 'Microsoft.App/managedEnvironments@2022-03-01' = {
  name: containerAppEnvironmentName
  location: location
  properties: {
   daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
   daprAIConnectionString: appInsights.properties.ConnectionString
   appLogsConfiguration: {
    destination: 'log-analytics'
    logAnalyticsConfiguration: {
      customerId: logAnalytics.properties.customerId
      sharedKey: logAnalytics.listKeys().primarySharedKey
    }
   } 
  }
}

resource daprComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-03-01' = {
  name: 'pubsub'
  parent: environment
  properties: {
    componentType: 'pubsub.azure.servicebus'
    version: 'v1'
    secrets: [
      {
        name: 'sb-root-connectionstring'
        value: listKeys('${serviceBus.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBus.apiVersion).primaryConnectionString
      }
    ]
    metadata: [
      {
        name: 'connectionString'
        secretRef: 'sb-root-connectionstring'
      }
    ]
    scopes: [
      checkoutContainerApp.name
      orderContainerApp.name
    ]
  }
}

resource checkoutContainerApp 'Microsoft.App/containerApps@2022-03-01' = {
  name: checkoutApp
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'container-registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: '${containerRegistry.name}.azurecr.io'
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'container-registry-password'
        }
      ]
      ingress: {
        external: false
        targetPort: targetPort
      }
      dapr: {
        enabled: true
        appId: checkoutApp
        appProtocol: 'http'
        appPort: targetPort
      }
    }
    template: {
      containers: [
        {
          image: checkoutImage
          name: checkoutApp
          env: [
            {
              name: 'APP_PORT'
              value: '${targetPort}'
            }
            {
              name: 'appinsightsconnectionstring'
              value: appInsights.properties.ConnectionString
            }
          ]
          resources: {
            cpu: '0.5'
            memory: '1.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource orderContainerApp 'Microsoft.App/containerApps@2022-03-01' = {
  name: orderProcessorApp
  location: location
  properties: {
   managedEnvironmentId: environment.id
   configuration: {
    activeRevisionsMode: 'Single'
    secrets: [
      {
        name: 'container-registry-password'
        value: containerRegistry.listCredentials().passwords[0].value
      }
      {
        name: 'sb-root-connectionstring'
        value: listKeys('${serviceBus.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBus.apiVersion).primaryConnectionString
      }
    ]
    registries: [
      {
        server: '${containerRegistry.name}.azurecr.io'
        username: containerRegistry.listCredentials().username
        passwordSecretRef: 'container-registry-password'
      }
    ]
    dapr: {
      enabled: true
      appId: orderProcessorApp
    }
   }
   template: {
    containers: [
      {
        image: orderProcessorImage
        name: orderProcessorApp
        env: [
          {
            name: 'appinsightsconnectionstring'
            value: appInsights.properties.ConnectionString
          }
        ]
        resources: {
          cpu: '0.5'
          memory: '1.0Gi'
        }
      }
    ]
    scale: {
      minReplicas: 1
      maxReplicas: 10
      rules: [
        {
          name: 'service-bus-scale-rule'
          custom: {
            type: 'azure-servicebus'
            metadata: {
              topicName: ordersTopic.name
              subscriptionName: orderProcessorApp
              messageCount: '10'
            }
            auth: [
              {
                secretRef: 'sb-root-connectionstring'
                triggerParameter: 'connection'
              }
            ]
          }
        }
      ]
    }
   } 
  }
  identity: {
    type: 'SystemAssigned'
  }
}
