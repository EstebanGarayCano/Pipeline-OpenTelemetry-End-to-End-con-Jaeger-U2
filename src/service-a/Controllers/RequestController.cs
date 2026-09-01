using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace ServiceA.Controllers;

[ApiController]
[Route("[controller]")]
public class RequestController : ControllerBase
{
    private static readonly ActivitySource ActivitySource = new("ServiceA");
    private readonly HttpClient _httpClient;
    private readonly ILogger<RequestController> _logger;
    private readonly IConfiguration _config;

    public RequestController(IHttpClientFactory factory, ILogger<RequestController> logger, IConfiguration config)
    {
        _httpClient = factory.CreateClient();
        _logger = logger;
        _config = config;
    }

    [HttpGet("/request")]
    public async Task<IActionResult> HandleRequest([FromQuery] string? input)
    {
        using var span = ActivitySource.StartActivity("handle-request");
        span?.SetTag("input.value", input ?? "default");

        _logger.LogInformation("service-a recibió request con input={Input}", input);

        using (var validationSpan = ActivitySource.StartActivity("validate-input"))
        {
            if (string.IsNullOrEmpty(input))
            {
                input = "default";
                validationSpan?.SetTag("validation.result", "used-default");
            }
            else
            {
                validationSpan?.SetTag("validation.result", "ok");
            }
        }

        var serviceBUrl = _config["SERVICE_B_URL"] ?? "http://localhost:8081";

        using (var callSpan = ActivitySource.StartActivity("call-service-b"))
        {
            callSpan?.SetTag("service.b.url", serviceBUrl);

            var response = await _httpClient.GetAsync($"{serviceBUrl}/process?input={input}");
            var body = await response.Content.ReadAsStringAsync();

            _logger.LogInformation("service-b respondió con status={Status}", response.StatusCode);

            span?.SetTag("response.status", (int)response.StatusCode);

            return Ok(new
            {
                service = "service-a",
                input,
                serviceBResponse = body,
                traceId = Activity.Current?.TraceId.ToString()
            });
        }
    }

    [HttpGet("/health")]
    public IActionResult Health() => Ok(new { status = "healthy", service = "service-a" });

    // Endpoint de prueba para demostrar detección de errores de autenticación en Grafana
    [HttpGet("/auth-test")]
    public IActionResult AuthTest([FromQuery] string? token)
    {
        _logger.LogWarning("Intento de acceso a recurso protegido sin token válido desde {Path}", HttpContext.Request.Path);
        if (token == "valid-token")
            return Ok(new { status = "authorized" });
        return Unauthorized(new { error = "Token inválido o ausente", service = "service-a" });
    }
}
