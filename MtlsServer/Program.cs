using Microsoft.AspNetCore.Server.Kestrel.Https;
using System.Security.Cryptography.X509Certificates;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenLocalhost(5000, listenOptions =>
    {
        listenOptions.UseHttps(httpsOptions =>
        {
            string certPath = Path.Combine(AppContext.BaseDirectory, "server.pfx");
            httpsOptions.ServerCertificate = X509CertificateLoader.LoadPkcs12FromFile(certPath, "senha123");

            httpsOptions.ClientCertificateMode = ClientCertificateMode.RequireCertificate;

            // POC: aceita qualquer certificado cliente. Em produção, validar emissor,
            // CN e validade antes de retornar true.
            httpsOptions.ClientCertificateValidation = (certificate, chain, errors) => true;
        });
    });
});

var app = builder.Build();

app.MapGet("/hello", (HttpContext context) =>
{
    var clientCertificate = context.Connection.ClientCertificate;

    return Results.Ok(new
    {
        message = "Conexão mTLS estabelecida com sucesso!",
        clientCertSubject = clientCertificate?.Subject ?? "Nenhum certificado recebido",
        timestamp = DateTime.UtcNow
    });
});

await app.RunAsync();