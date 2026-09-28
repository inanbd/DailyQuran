# syntax=docker/dockerfile:1
#
# The Daily Quran website. Build it from the repository root, so the site can
# read the app's own Qur'an data, privacy policy and changelog:
#
#   docker build -f website/Dockerfile -t dailyquran-web .
#   docker run -p 8080:8080 -e Contact__Recipient=you@example.com ... dailyquran-web
#
# website/Dockerfile.dockerignore keeps the Flutter app out of the build context.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY website/src/DailyQuran.Web/DailyQuran.Web.csproj website/src/DailyQuran.Web/
RUN dotnet restore website/src/DailyQuran.Web/DailyQuran.Web.csproj

COPY assets/data/ assets/data/
COPY PRIVACY.md CHANGELOG.md ./
COPY website/src/ website/src/
RUN dotnet publish website/src/DailyQuran.Web/DailyQuran.Web.csproj \
    --configuration Release --no-restore --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app

# Somewhere the app user may keep its data-protection keys. Mount a volume
# here so the contact form's tokens survive a redeploy.
RUN mkdir /keys && chown "$APP_UID" /keys

COPY --from=build /app .

# Most hosts terminate HTTPS in front of the container and forward the
# original scheme and address; the site trusts those headers.
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_FORWARDEDHEADERS_ENABLED=true \
    DataProtection__KeysPath=/keys

USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "DailyQuran.Web.dll"]
