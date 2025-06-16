# **Advanced LXC Script for Running Jackett on RISC-V Architecture**

---

## **Overview** 🎯

This script automates the deployment of an LXC container running the **Jackett** application on RISC-V hardware with **advanced multi-interface networking capabilities**. Jackett is a proxy server that allows for seamless integration of torrent indexers with popular media server software like Sonarr and Radarr.

The script provides:
- **Advanced Multi-Interface Networking** with automatic failover between network interfaces
- **DHCP Static IP Management** using client identifiers for consistent IP assignments
- **Continuous Network Monitoring** with automatic interface switching when failures occur
- **Real-time Interface Health Checking** that tests actual internet connectivity, not just link status
- **Comprehensive Configuration Management** with multiple override levels and persistent storage
- **Custom MAC Address Support** with flexible override options
- Builds and runs **Jackett** under **.NET** (configured for RISC-V architecture)
- Configures a container with an **isolated environment** to run Jackett
- Ensures **persistent storage** for Jackett configuration and keys
- Publishes the container as a **reusable image** for easy replication

---

## **Key Features** ✨

### **🌐 Advanced Networking**
- **Multi-Interface Support**: Automatically selects the best available interface from a priority list (end0, end1, wlan0)
- **Intelligent Failover**: Continuously monitors interface health and switches automatically when failures occur
- **Real Connectivity Testing**: Tests actual internet access, not just interface link status
- **DHCP Static IP Management**: Uses client identifiers to maintain consistent IP addresses across reboots
- **Custom MAC Address Support**: Configure custom MAC addresses with multiple override options
- **Background Monitoring**: Runs a systemd service that monitors network health 24/7

### **🔧 Configuration Management**
- **Persistent Configuration**: Automatically saves network settings to `/etc/jackett-network.conf`
- **Multi-Level Overrides**: Support for configuration file, environment variables, and command-line overrides
- **Flexible MAC Address Management**: Configure MAC addresses globally or per-operation
- **Runtime Configuration Changes**: Modify settings without rebuilding the container
- **Configuration Validation**: Built-in validation and status reporting

### **🔒 Security & Isolation**
- **RISC-V Architecture Support**: Utilizes a prebuilt RISC-V-compatible .NET SDK
- **Automated Jackett Deployment**: Automatically clones, builds, and configures Jackett for the container
- **Enhanced Security**: Comprehensive security validation with LXC unprivileged containers
- **Persistent Storage**: Stores configuration and keys outside the container, ensuring data longevity
- **Container Image Publishing**: Creates an LXC image from the configured container for future use

### **🛠️ Management & Monitoring**
- **Network Management Script**: Comprehensive tool for monitoring and managing network interfaces
- **Real-time Status Monitoring**: Check interface health, container status, and service accessibility
- **Manual Interface Switching**: Force switch to specific interfaces when needed
- **Detailed Logging**: Complete audit trail of all network changes and failures
- **Configuration Display**: View current configuration and available override options

---

## **Prerequisites** 🛠️

1. **Host System**:
   - A host machine with LXC/LXD installed and configured.
   - A RISC-V-based hardware platform (e.g., Orange Pi RV2, HiFive Unmatched board).
   - A valid network connection (a standard router with DHCP enabled is needed for macvlan functionality).
   - Ubuntu 20.04/22.04/24.04 (or compatible Linux distribution).

2. **Required Tools**:
   - Bash shell
   - `lxc`/`lxd` tools installed and properly configured.
   - Administrative privileges for creating containers.

3. **Important Information**:
   - Ensure your router supports DHCP and is configured to assign IP addresses automatically.
   - Replace placeholder interface names (like `eth0`) in **macvlan configuration** with your actual network interface.

---

## **Configuration Options** ⚙️

### **Core Configuration Variables**

| Variable Name          | Default Value                     | Description                                                           |
|------------------------|-----------------------------------|-----------------------------------------------------------------------|
| `CT_NAME`             | `dotnet-jackett`                 | Name of the LXC container being created.                              |
| `IMAGE_ALIAS`         | `dotnet-jackett-riscv`         | Alias for the published image, used to create future containers.      |
| `PERSISTENT_STORAGE`  | `/var/lib/lxc-jackett-data`      | Host directory to store Jackett configuration persistently.           |
| `UBUNTU_IMAGE`        | `ubuntu:24.04`                  | Ubuntu base image for the LXC container.                              |
| `DOTNET_SDK_URL`      | *(RISC-V-specific URL)*          | Location of the RISC-V `.NET SDK` tarball hosting for download.        |

### **Advanced Networking Configuration** 🌐

| Variable Name               | Default Value                           | Description                                                     |
|-----------------------------|----------------------------------------|-----------------------------------------------------------------|
| `INTERFACE_PRIORITY_LIST`   | `("end0" "end1" "wlan0")`             | **Priority order of interfaces to try** - customize for your hardware |
| `USE_ADVANCED_NETWORKING`   | `true`                                 | Enable advanced multi-interface networking and failover         |
| `DHCP_CLIENT_ID`           | `jackett-riscv-$(hostname)`           | Unique DHCP client identifier for consistent IP assignment      |
| `DESIRED_STATIC_IP`        | `"192.168.8.138"`                    | Requested static IP (DHCP may assign different IP)             |
| `CONNECTIVITY_TEST_HOSTS`   | `("8.8.8.8" "1.1.1.1" "208.67.222.222")` | Hosts used to test actual internet connectivity            |
| `INTERFACE_CHECK_INTERVAL`  | `60`                                   | Seconds between interface health checks                         |
| `FAILOVER_SCRIPT`          | `/usr/local/bin/jackett-interface-monitor.sh` | Path to the network monitoring daemon script       |
| `NETWORK_MONITOR_SERVICE`  | `jackett-network-monitor`             | Name of the systemd monitoring service                         |
| `HOST_INTERFACE`           | `eth0`                                 | Fallback interface if priority interfaces are unavailable      |

### **Jackett Customization Configuration** 🎛️

| Variable Name               | Default Value                           | Description                                                     |
|-----------------------------|----------------------------------------|-----------------------------------------------------------------|
| `DESIRED_MAC_ADDRESS`      | `"02:16:E8:F8:95:41"`                 | Custom MAC address for container (leave empty for auto-generated) |
| `JACKETT_API_KEY`          | `""`                                   | Custom API key for Jackett (leave empty for auto-generated)    |
| `JACKETT_STARTUP_DELAY`    | `30`                                   | Seconds to wait for Jackett to fully start before verification |

### **Optional Steps Configuration** 📦

| Variable Name               | Default Value                           | Description                                                     |
|-----------------------------|----------------------------------------|-----------------------------------------------------------------|
| `ENABLE_CONTAINER_PUBLISHING` | `false`                               | Set to true to publish container as reusable image             |
| `ENABLE_IMAGE_EXPORT`      | `false`                                | Set to true to export image to disk (requires publishing=true) |
| `IMAGE_EXPORT_PATH`        | `"/tmp"`                               | Directory to save exported image                                |

### **Configuration File System** 📋

The build script automatically creates `/etc/jackett-network.conf` with all configuration parameters:

```bash
# Example /etc/jackett-network.conf
CT_NAME="dotnet-jackett"
NETWORK_MONITOR_SERVICE="jackett-network-monitor"
INTERFACE_PRIORITY_LIST=("end0" "end1" "wlan0")
DESIRED_MAC_ADDRESS="02:16:E8:F8:95:41"
DHCP_CLIENT_ID="jackett-riscv-hostname"
DESIRED_STATIC_IP="192.168.8.138"
CONNECTIVITY_TEST_HOSTS=("8.8.8.8" "1.1.1.1" "208.67.222.222")
INTERFACE_CHECK_INTERVAL=60
```

**🎯 Interface Priority Configuration:**
- **`end0`**: Typically the first Ethernet interface on RISC-V boards
- **`end1`**: Second Ethernet interface (if available)  
- **`wlan0`**: WiFi interface as fallback
- **Customize this list** based on your specific hardware setup

---

## **Usage Instructions** 🚀

### **1. Clone this Repository**
Clone this GitHub repository to your local machine:
```bash
git clone https://github.com/Alexgolshtein/Jacket-RISC-V.git
cd Jacket-RISC-V
```

### **2. Customize the Script**
Before running the script, you can adjust configuration variables in the script to match your requirements. Key customizations include:

```bash
# Edit the script to customize for your hardware
nano build_and_run_jackett.sh

# Key variables to customize:
INTERFACE_PRIORITY_LIST=("end0" "end1" "wlan0")  # Your actual interfaces
DESIRED_MAC_ADDRESS="02:16:E8:F8:95:41"          # Your custom MAC (optional)
DESIRED_STATIC_IP="192.168.1.200"                # Your preferred IP (optional)
```

### **3. Run the Script**
Make the script executable and run it:
```bash
chmod +x build_and_run_jackett.sh
./build_and_run_jackett.sh
```

### **4. Verify the Deployment**
Once the script completes, you'll see a comprehensive status report:

```
╔════════════════════════════════════════════════════════════════╗
║                    SETUP COMPLETE - STATUS REPORT             ║
╚════════════════════════════════════════════════════════════════╝

🔧 NETWORKING CONFIGURATION:
   • Advanced Multi-Interface Networking: ENABLED
   • Active Interface: end0
   • Custom MAC Address: 02:16:E8:F8:95:41
   • Interface Priority List: end0 end1 wlan0
   • DHCP Client ID: jackett-riscv-yourhostname
   • Network Monitor Service: jackett-network-monitor.service

🌐 CONTAINER NETWORK STATUS:
   • Current Interface: end0
   • Requested IP Address: 192.168.8.138
   • Actual IP Address: 192.168.8.138
   • IP Status: ✓ DHCP granted requested IP
   • Jackett Web Interface: http://192.168.8.138:9117

📡 MACVLAN NETWORKING IMPORTANT NOTES:
   • Container is accessible from ALL network devices EXCEPT the host
   • Host cannot ping/access container IP directly (this is normal)
   • Other PCs/phones/devices on network can access Jackett normally
   • To test from host: lxc exec dotnet-jackett -- curl http://localhost:9117

🔒 SECURITY CONFIGURATION:
   • Container Type: Unprivileged LXC container
   • Host Security: Container root = unprivileged host user (UID 165536+)
   • Validation: All security checks passed ✓
```

---

## **Network Management & Monitoring** 🔧

The system includes a comprehensive network management tool (`jackett-network-manager.sh`) with advanced configuration override capabilities.

### **Configuration Priority System**

The network manager uses a three-level configuration priority system:

1. **🥇 Highest Priority**: Command-line arguments (`--mac` option)
2. **🥈 Medium Priority**: Environment variables (`JACKETT_MAC_ADDRESS`, etc.)
3. **🥉 Base Priority**: Configuration file (`/etc/jackett-network.conf`)
4. **🏳️ Fallback**: Default hardcoded values

### **Command-Line Usage**

#### **Basic Commands**
```bash
# Show current system status
./jackett-network-manager.sh status

# Show recent network monitor logs
./jackett-network-manager.sh logs [lines]

# Display current configuration and override options
./jackett-network-manager.sh show-config

# Get help and usage information
./jackett-network-manager.sh help
```

#### **Network Management Commands**
```bash
# List all available network interfaces
./jackett-network-manager.sh list-interfaces

# Test connectivity on specific interface
./jackett-network-manager.sh test-interface wlan0

# Manually switch to specific interface
./jackett-network-manager.sh switch end1

# Restart the network monitoring service
./jackett-network-manager.sh restart-monitor
```

#### **MAC Address Override Options**
```bash
# Override MAC address via command line
./jackett-network-manager.sh --mac=02:16:E8:F8:95:41 switch end0
./jackett-network-manager.sh --mac 02:16:E8:F8:95:41 status

# Use configuration from file (default behavior)
./jackett-network-manager.sh status
```

### **Environment Variable Overrides**

You can override any configuration parameter using environment variables:

```bash
# Override MAC address
JACKETT_MAC_ADDRESS="02:16:E8:F8:95:41" ./jackett-network-manager.sh status

# Override container name
JACKETT_CT_NAME="my-jackett" ./jackett-network-manager.sh status

# Override monitor service name
JACKETT_MONITOR_SERVICE="my-network-monitor" ./jackett-network-manager.sh status

# Override DHCP client ID
JACKETT_DHCP_CLIENT_ID="my-unique-id" ./jackett-network-manager.sh switch end0

# Override static IP request
JACKETT_STATIC_IP="192.168.1.100" ./jackett-network-manager.sh switch wlan0

# Multiple overrides
JACKETT_MAC_ADDRESS="02:16:E8:F8:95:41" JACKETT_CT_NAME="my-jackett" ./jackett-network-manager.sh status
```

### **Configuration Display Command**

Use the `show-config` command to see current configuration and all available override options:

```bash
./jackett-network-manager.sh show-config
```

**Example Output:**
```
╔═══════════════════════════════════════════════════════════════════╗
║                      CURRENT CONFIGURATION                       ║
╚═══════════════════════════════════════════════════════════════════╝

📁 Configuration Source:
   ✓ Config file: /etc/jackett-network.conf
   📅 Modified: 2024-01-15 14:30:25

🐳 Container Configuration:
   Container Name: dotnet-jackett
   Monitor Service: jackett-network-monitor

🌐 Network Configuration:
   Interface Priority: end0 end1 wlan0
   MAC Address: 02:16:E8:F8:95:41 (custom)
   DHCP Client ID: jackett-riscv-hostname
   Requested Static IP: 192.168.8.138

🔧 Available Overrides:
   Environment Variables:
     JACKETT_MAC_ADDRESS    - Override MAC address
     JACKETT_CT_NAME        - Override container name
     JACKETT_MONITOR_SERVICE - Override monitor service name
     JACKETT_DHCP_CLIENT_ID - Override DHCP client ID
     JACKETT_STATIC_IP      - Override static IP request
   Command Line:
     --mac MAC_ADDRESS      - Override MAC address
```

### **Advanced Usage Examples**

#### **Status Monitoring with Overrides**
```bash
# Check status with custom MAC address
./jackett-network-manager.sh --mac=02:AA:BB:CC:DD:EE status

# Check status for different container
JACKETT_CT_NAME="test-jackett" ./jackett-network-manager.sh status

# Monitor logs with environment overrides
JACKETT_MAC_ADDRESS="02:16:E8:F8:95:41" ./jackett-network-manager.sh logs 100
```

#### **Interface Switching with Custom Configuration**
```bash
# Switch interface with custom MAC address
./jackett-network-manager.sh --mac=02:16:E8:F8:95:41 switch wlan0

# Switch with multiple overrides
JACKETT_DHCP_CLIENT_ID="test-client" JACKETT_STATIC_IP="192.168.1.150" \
./jackett-network-manager.sh --mac=02:AA:BB:CC:DD:EE switch end1
```

#### **Testing and Diagnostics**
```bash
# Test interface with custom settings
JACKETT_MAC_ADDRESS="02:16:E8:F8:95:41" ./jackett-network-manager.sh test-interface end0

# List interfaces with custom container name
JACKETT_CT_NAME="my-jackett" ./jackett-network-manager.sh list-interfaces
```

---

## **Advanced Networking Architecture** 🏗️

### **How Multi-Interface Failover Works**

The system implements a sophisticated networking architecture with several key components:

#### **1. Interface Selection & Health Monitoring**
- **Priority-Based Selection**: Tests interfaces in order (end0 → end1 → wlan0) and selects the first working one
- **Real Connectivity Testing**: Goes beyond link status - tests actual internet connectivity using multiple DNS servers
- **Continuous Monitoring**: Background daemon checks interface health every 60 seconds (configurable)

#### **2. DHCP Static IP Management**
- **Client Identifier Strategy**: Uses unique DHCP client identifiers to encourage consistent IP assignment
- **MAC Address Management**: Supports custom MAC addresses with multiple override levels
- **Router Compatibility**: Works with most home routers that support DHCP reservations

#### **3. Automatic Failover Process**
```
Interface Failed → Test Alternative Interfaces → Reconfigure Container → Verify Jackett Access → Update Routing
```

#### **4. Container Network Management**
- **Seamless Switching**: Container automatically gets new IP on the new interface
- **Service Continuity**: Jackett service remains available during interface switches
- **State Persistence**: Tracks current interface and maintains logs of all changes

### **Configuration Management System** 🔧

The solution provides a comprehensive configuration management system:

#### **Configuration File Creation**
The build script automatically creates `/etc/jackett-network.conf` containing:
- All network configuration parameters
- Container and service names
- Interface priorities and MAC addresses
- DHCP and connectivity settings

#### **Override Hierarchy**
1. **Command-line arguments** (highest priority)
2. **Environment variables** (medium priority)  
3. **Configuration file** (base priority)
4. **Default values** (fallback)

#### **Runtime Configuration Changes**
- Modify settings without container rebuild
- Test configurations before applying
- Validate settings and show current state

---

## **What's Inside the Scripts?** 📜

### **Enhanced Main Script** (`build_and_run_jackett.sh`)

The main script follows this enhanced workflow:

1. **🔧 Configuration Setup**:
   - Parse configuration variables
   - Validate network settings
   - Create system configuration file

2. **🌐 Advanced Interface Selection**:
   - Scan all priority interfaces for availability and connectivity
   - Test actual internet access using multiple DNS servers
   - Select the best available interface based on priority and health

3. **📦 Enhanced Container Setup**:
   - Create container with advanced networking configuration
   - Set up DHCP client with unique identifier for static IP attempts
   - Configure custom MAC address management

4. **👁️ Network Monitoring Daemon Creation**:
   - Create `/usr/local/bin/jackett-interface-monitor.sh` monitoring script
   - Set up systemd service for continuous interface monitoring
   - Implement automatic failover logic with health checking
   - Configure comprehensive logging and state tracking

5. **🎛️ Standard Jackett Setup**:
   - Install prerequisites and .NET SDK
   - Clone, builds, and configure Jackett
   - Set up Jackett as a systemd service with security validation
   - Configure persistent storage for configuration and keys

6. **✅ System Integration & Verification**:
   - Start network monitoring service
   - Verify all services are working correctly
   - Optionally publish container as reusable image
   - Provide comprehensive status reporting

### **Network Management Tool** (`jackett-network-manager.sh`)

The network manager provides:

1. **📋 Configuration Loading**:
   - Load settings from `/etc/jackett-network.conf`
   - Apply environment variable overrides
   - Parse command-line arguments
   - Validate configuration hierarchy

2. **📊 Status Monitoring**:
   - Real-time container and service status
   - Interface health and connectivity testing
   - Network accessibility verification
   - Service performance monitoring

3. **🔧 Manual Management**:
   - Force interface switching with custom settings
   - Network diagnostics and testing
   - Service restart and management
   - Configuration display and validation

4. **📝 Logging & Diagnostics**:
   - Monitor log analysis
   - Interface testing and validation
   - Error reporting and troubleshooting
   - Configuration debugging

---

## **Troubleshooting** 🛠️

### **Configuration Issues** ⚙️

1. **Configuration File Missing**:
   ```bash
   ./jackett-network-manager.sh show-config    # Check configuration source
   ls -la /etc/jackett-network.conf           # Verify file exists
   ```
   - **Solution**: Re-run the build script to recreate configuration file

2. **Override Not Working**:
   ```bash
   # Test override explicitly
   JACKETT_MAC_ADDRESS="02:AA:BB:CC:DD:EE" ./jackett-network-manager.sh show-config
   ./jackett-network-manager.sh --mac=02:AA:BB:CC:DD:EE show-config
   ```
   - **Solution**: Check override syntax and priority hierarchy

3. **Invalid MAC Address**:
   ```bash
   # Check current MAC configuration
   ./jackett-network-manager.sh show-config
   ```
   - **Solution**: Use valid MAC format (XX:XX:XX:XX:XX:XX)

### **Network Issues** 🌐

4. **No Interfaces Available**:
   ```bash
   ./jackett-network-manager.sh list-interfaces    # Check available interfaces
   ./jackett-network-manager.sh test-interface end0 # Test specific interface
   ```
   - Verify interface names match your hardware (`ip link show`)
   - Update `INTERFACE_PRIORITY_LIST` in the script for your specific setup

5. **Container Fails to Get IP Address**:
   ```bash
   ./jackett-network-manager.sh status             # Check current status
   journalctl -u jackett-network-monitor -n 50     # Check monitor logs
   ```
   - Verify DHCP is enabled on your router
   - Check if interface is actually up and connected
   - Try manually switching to a different interface

6. **Interface Failover Not Working**:
   ```bash
   systemctl status jackett-network-monitor        # Check monitor service
   ./jackett-network-manager.sh restart-monitor    # Restart monitoring
   tail -f /var/log/jackett-network-monitor.log    # Watch real-time logs
   ```

7. **Static IP Not Consistent**:
   - Configure DHCP reservation on your router using the container's MAC address
   - Check if your router supports DHCP client identifiers
   - Verify `DESIRED_STATIC_IP` configuration

### **Service Issues** 🔧

8. **Jackett Service Fails to Start**:
   ```bash
   lxc exec dotnet-jackett -- systemctl status jackett.service
   lxc exec dotnet-jackett -- journalctl -u jackett -n 50
   ```

9. **Container Networking Problems**:
   ```bash
   lxc exec dotnet-jackett -- ip addr show         # Check container IP
   lxc exec dotnet-jackett -- ping 8.8.8.8        # Test connectivity
   ```

10. **Monitor Service Issues**:
    ```bash
    systemctl restart jackett-network-monitor       # Restart monitor
    journalctl -u jackett-network-monitor -f        # Follow logs
    ```

### **Advanced Diagnostics** 🔍

11. **Comprehensive Status Check**:
    ```bash
    ./jackett-network-manager.sh status             # Full system status
    ./jackett-network-manager.sh show-config        # Configuration analysis
    ```

12. **Manual Interface Testing**:
    ```bash
    # Test each interface manually
    ./jackett-network-manager.sh test-interface end0
    ./jackett-network-manager.sh test-interface end1
    ./jackett-network-manager.sh test-interface wlan0
    ```

13. **Configuration Debugging**:
    ```bash
    # Test different configuration scenarios
    JACKETT_MAC_ADDRESS="test" ./jackett-network-manager.sh show-config
    ./jackett-network-manager.sh --mac=test show-config
    ```

14. **Container Shell Access**:
    ```bash
    lxc exec dotnet-jackett -- bash                # Interactive container access
    ```

15. **Reset Network Configuration**:
    ```bash
    # If everything fails, restart with fresh networking
    lxc restart dotnet-jackett
    systemctl restart jackett-network-monitor
    ```

### **Log Locations** 📋
- **Network Monitor**: `/var/log/jackett-network-monitor.log`
- **Current Interface**: `/tmp/jackett-current-interface` 
- **Configuration File**: `/etc/jackett-network.conf`
- **Systemd Services**: `journalctl -u service-name`
- **Jackett Application**: Inside container at `/opt/jackett-published/logs/`

---

## **Complete Command Reference** 📚

### **Build Script** (`build_and_run_jackett.sh`)
```bash
# Basic usage
./build_and_run_jackett.sh

# The script automatically:
# - Creates /etc/jackett-network.conf with all settings
# - Sets up advanced networking with configured interfaces
# - Creates network monitoring daemon
# - Configures Jackett with custom API key and MAC address
# - Optionally publishes and exports container image
```

### **Network Manager** (`jackett-network-manager.sh`)

#### **Status and Information Commands**
```bash
./jackett-network-manager.sh status                  # Show current status
./jackett-network-manager.sh show-config             # Display configuration
./jackett-network-manager.sh list-interfaces         # List all interfaces
./jackett-network-manager.sh help                    # Show help message
```

#### **Network Management Commands**
```bash
./jackett-network-manager.sh test-interface <iface>  # Test specific interface
./jackett-network-manager.sh switch <interface>      # Switch to interface
./jackett-network-manager.sh restart-monitor         # Restart monitoring
```

#### **Logging Commands**
```bash
./jackett-network-manager.sh logs                    # Show recent logs (20 lines)
./jackett-network-manager.sh logs 50                 # Show last 50 log entries
./jackett-network-manager.sh logs 100                # Show last 100 log entries
```

#### **Override Options**
```bash
# Command-line MAC override
./jackett-network-manager.sh --mac=XX:XX:XX:XX:XX:XX <command>
./jackett-network-manager.sh --mac XX:XX:XX:XX:XX:XX <command>

# Environment variable overrides
JACKETT_MAC_ADDRESS="XX:XX:XX:XX:XX:XX" ./jackett-network-manager.sh <command>
JACKETT_CT_NAME="container-name" ./jackett-network-manager.sh <command>
JACKETT_MONITOR_SERVICE="service-name" ./jackett-network-manager.sh <command>
JACKETT_DHCP_CLIENT_ID="client-id" ./jackett-network-manager.sh <command>
JACKETT_STATIC_IP="192.168.1.100" ./jackett-network-manager.sh <command>
```

#### **Complete Usage Examples**
```bash
# Basic status check
./jackett-network-manager.sh status

# Switch interface with custom MAC
./jackett-network-manager.sh --mac=02:16:E8:F8:95:41 switch wlan0

# Check configuration with environment override
JACKETT_MAC_ADDRESS="02:AA:BB:CC:DD:EE" ./jackett-network-manager.sh show-config

# Test interface with multiple overrides
JACKETT_DHCP_CLIENT_ID="test-id" JACKETT_STATIC_IP="192.168.1.200" \
./jackett-network-manager.sh --mac=02:16:E8:F8:95:41 test-interface end0

# Monitor logs with custom container name
JACKETT_CT_NAME="my-jackett" ./jackett-network-manager.sh logs 100
```

---

## **Contributing** 🤝

If you'd like to enhance or improve this script, feel free to submit a pull request or open an issue in this repository. Contributions are welcome!

Areas for contribution:
- Additional network interface types
- Enhanced monitoring capabilities  
- Configuration validation improvements
- Documentation and examples
- Testing on different RISC-V hardware

---

## **License** 📄

This script is available under the **MIT License**. See the [LICENSE](./LICENSE) file for more details.

---

## **Acknowledgments** 🌟

Big thanks to Dmitry Kurtaev @dkurt for his .NET build for RISC-V https://github.com/dkurt/dotnet_riscv

Big thanks to the Jackett and .NET open-source communities for making tools available for RISC-V development.

---
