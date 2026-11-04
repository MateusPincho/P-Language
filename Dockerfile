FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

# .NET SDK 8.0 (Microsoft feed), Java runtime (>= 11), python3 for tools/simulate_logs.py
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget git python3 default-jre \
 && wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/ms.deb \
 && dpkg -i /tmp/ms.deb && rm /tmp/ms.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends dotnet-sdk-8.0 \
 && rm -rf /var/lib/apt/lists/*

# Non-root user matching the host user, so PGenerated/ and PCheckerOutput/
# written into the bind mount are owned by you, not root.
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} dev && useradd -m -u ${UID} -g ${GID} -s /bin/bash dev
USER dev
ENV PATH="/home/dev/.dotnet/tools:${PATH}"

# P tool (leave P_VERSION empty for the latest release)
ARG P_VERSION=
RUN dotnet tool install --global P ${P_VERSION:+--version $P_VERSION}

WORKDIR /workspace
CMD ["bash"]
