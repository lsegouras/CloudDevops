# ---- build ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# restore primeiro, para aproveitar o cache de layer (código não invalida o restore)
COPY ["YoutubeLiveApp.csproj", "./"]
RUN dotnet restore "YoutubeLiveApp.csproj"

# código e publish
COPY . .
RUN dotnet publish "YoutubeLiveApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

# ---- runtime ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# curl só para o HEALTHCHECK interno (imagem aspnet não traz curl)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

# Kestrel escuta em 8080 por padrão no .NET 8 sob usuário não-root
ENV ASPNETCORE_HTTP_PORTS=8080
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080

# usuário não-root pré-existente na imagem (app, UID 1654)
USER app

# A app monta o pipeline sob app.Map("/backend", ...), então o health real é /backend/health
HEALTHCHECK --interval=15s --timeout=3s --start-period=15s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/backend/health || exit 1

ENTRYPOINT ["dotnet", "YoutubeLiveApp.dll"]
