#!/usr/bin/env bash
set -euo pipefail

# Configuration: adjust as needed
CT_NAME="dotnet-jackett"
IMAGE_ALIAS="dotnet-jackett-riscv24"
UBUNTU_IMAGE="ubuntu:24.04"
DOTNET_SDK_URL="https://github.com/dkurt/dotnet_riscv/releases/download/v8.0.101/dotnet-sdk-8.0.101-linux-riscv64-gcc.tar.gz"
DOTNET_INSTALL_DIR="/opt/dotnet"
JACKETT_DIR="/opt/Jackett"
JACKETT_SERVICE_NAME="jackett"
# If you need a specific Jackett release, set JACKETT_TAG, otherwise it'll build default branch
JACKETT_REPO="https://github.com/Jackett/Jackett.git"
JACKETT_TAG=""   # e.g. "v0.20.XXX" or leave empty for latest main branch

# 1. Launch a fresh container
echo "Launching container ${CT_NAME} from ${UBUNTU_IMAGE}..."
lxc delete "${CT_NAME}" --force || true
lxc launch "${UBUNTU_IMAGE}" "${CT_NAME}"

# Wait a bit for cloud-init inside container to finish
echo "Waiting for container to be ready..."
sleep 5

# 2. Update & install prerequisites
echo "--> 2. Updating apt and installing prerequisites..."
lxc exec "${CT_NAME}" -- bash -eux -c "
apt update
DEBIAN_FRONTEND=noninteractive apt install -y wget tar git libssl-dev libkrb5-3 libicu-dev liblttng-ust-dev libcurl4 libuuid1 zlib1g
"

# 3. Download and install .NET SDK into /opt/dotnet
echo "--> 3.1 Installing .NET SDK inside container..."
lxc exec "${CT_NAME}" -- bash -eux -c "
mkdir -p ${DOTNET_INSTALL_DIR}
cd /tmp
wget -O dotnet-sdk-riscv.tar.gz '${DOTNET_SDK_URL}'
tar -xzvf dotnet-sdk-riscv.tar.gz -C ${DOTNET_INSTALL_DIR}
# Symlink or wrapper so 'dotnet' is on PATH
ln -sf ${DOTNET_INSTALL_DIR}/dotnet /usr/local/bin/dotnet
# Verify installation
dotnet --info
"

echo "--> 3.2 fix NuGet config"

lxc exec "${CT_NAME}" -- bash -eux -c "
rm -rf /root/.nuget/NuGet
mkdir -p /root/.nuget/NuGet
cat > /root/.nuget/NuGet/NuGet.Config <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
EOF
"


# 4. Clone Jackett and build/publish
echo "--> 4. Cloning and building Jackett inside container..."
# Determine target RID: linux-riscv64
# We assume the riscv64 SDK supports RID linux-riscv64. Adjust if needed.
TARGET_RID="linux-riscv64"

echo " --> 4.1 # Clone"

lxc exec "${CT_NAME}" -- bash -eux -c "
if [ -d '${JACKETT_DIR}' ]; then rm -rf '${JACKETT_DIR}'; fi
git clone '${JACKETT_REPO}' '${JACKETT_DIR}'
cd '${JACKETT_DIR}'
if [ -n '${JACKETT_TAG}' ]; then
  git checkout '${JACKETT_TAG}'
fi
"

echo " --> 4.2 # Build"

lxc exec "${CT_NAME}" -- bash -eux -c "
# Got to jacket server folder
cd /opt/Jackett/src/Jackett.Server

# Build/publish:
# Use Release configuration, target the riscv64 runtime identifier
# If Jackett's project file supports that RID; if not, may need to edit csproj.
dotnet publish Jackett.Server.csproj -c Release -r ${TARGET_RID} -f net8.0 --self-contained false -o /opt/jackett-published
# Note: If dotnet publish errors about unsupported RID, manual adjustments may be needed.
"

# 5. Create a systemd service inside the container to run Jackett at startup
echo "--> 5. Setting up Jackett service inside container..."
# Prepare a service file content
read -r -d '' SERVICE_FILE << 'EOF'
[Unit]
Description=Jackett Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/jackett-published
ExecStart=/usr/local/bin/dotnet /opt/jackett-published/jackett.dll --NoRestart
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Push the service file into the container
echo "--> 5-2. Uploading systemd service..."
# Use a here-doc to create the file via lxc exec tee
lxc exec "${CT_NAME}" -- bash -eux -c "tee /etc/systemd/system/${JACKETT_SERVICE_NAME}.service > /dev/null << 'EOF'
$SERVICE_FILE
EOF"

# Enable the service
lxc exec "${CT_NAME}" -- bash -eux -c "
systemctl daemon-reload
systemctl enable ${JACKETT_SERVICE_NAME}.service
"

# 6. (Optional) Expose ports: Jackett default is 9117. Add a proxy device or use IPv4 NAT.
# For LXD NAT, no host binding needed; inside container Jackett listens on 0.0.0.0:9117 by default.
# You can test by 'lxc exec ... curl http://localhost:9117' or map host port:
# lxc config device add ${CT_NAME} jackettport proxy listen=tcp:0.0.0.0:9117 connect=tcp:127.0.0.1:9117

# Example: map host port 9117 → container 9117
echo "--> 6. Mapping host port 9117 to container..."
lxc config device add "${CT_NAME}" jackettport proxy listen=tcp:0.0.0.0:9117 connect=tcp:127.0.0.1:9117

# 7. Start the service inside container and verify
echo "--> 7. Starting Jackett service..."
lxc exec "${CT_NAME}" -- bash -eux -c "
systemctl start ${JACKETT_SERVICE_NAME}.service
sleep 3
# Check service status
systemctl is-active ${JACKETT_SERVICE_NAME}.service
"

# 8. Commit the container as a reusable image
echo "--> 8. Stopping container to commit image..."
lxc stop "${CT_NAME}"
echo "Publishing container as image alias '${IMAGE_ALIAS}'..."
lxc publish "${CT_NAME}" --alias "${IMAGE_ALIAS}"

echo "Done. New image '${IMAGE_ALIAS}' is available. You can now launch containers from it:"
echo "  lxc launch ${IMAGE_ALIAS} new-jackett-instance"
