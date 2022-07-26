using System.Text.Json.Serialization;
using Dapr;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();

var app = builder.Build();

var logger = app.Logger;

app.UseCloudEvents();
app.MapSubscribeHandler();

if (app.Environment.IsDevelopment()) { app.UseDeveloperExceptionPage(); }

app.MapPost("/orders", [Topic("pubsub", "orders")] (Order order) =>
{
    logger.LogInformation("Subscriber received: " + order);
    return Results.Ok(order);
});

await app.RunAsync();

public record Order([property: JsonPropertyName("orderId")] int OrderId);