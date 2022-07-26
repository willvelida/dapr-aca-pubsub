using Dapr.Client;
using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.Extensions.Configuration;
using System.Text.Json.Serialization;

var configuration = new ConfigurationBuilder()
    .AddEnvironmentVariables()
    .Build();

TelemetryConfiguration telemetryConfiguration = TelemetryConfiguration.CreateDefault();
telemetryConfiguration.ConnectionString = configuration.GetValue<string>("appinsightsconnectionstring");

var telemetryClient = new TelemetryClient(telemetryConfiguration);

for (int i = 0; i <= 10; i++)
{
    var order = new Order(i);
    using var client = new DaprClientBuilder().Build();

    await client.PublishEventAsync("pubsub", "orders", order);
    telemetryClient.TrackTrace("Published data: " + order);

    await Task.Delay(TimeSpan.FromSeconds(1));
}

public record Order([property: JsonPropertyName("orderId")] int OrderId);