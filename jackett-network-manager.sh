#!/usr/bin/env bash
set -euo pipefail

# Load configuration from system config file (created by build_and_run_jackett.sh)
CONFIG_FILE="/etc/jackett-network.conf"

# Default configuration (fallback values)
CT_NAME="dotnet-jackett"
NETWORK_MONITOR_SERVICE="jackett-network-monitor"
CURRENT_INTERFACE_FILE="/tmp/jackett-current-interface"
LOG_FILE="/var/log/jackett-network-monitor.log"
INTERFACE_PRIORITY_LIST=("end0" "end1" "wlan0")
DESIRED_MAC_ADDRESS=""  # Will be loaded from config file
DHCP_CLIENT_ID=""
DESIRED_STATIC_IP=""
CONNECTIVITY_TEST_HOSTS=("8.8.8.8" "1.1.1.1" "208.67.222.222")
JACKETT_API_KEY=""
JACKETT_STARTUP_DELAY=140
JACKETT_ADDITIONAL_OPTIONS=""

# Load configuration from file if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo "📋 Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    echo "✓ Configuration loaded successfully"
else
    echo "⚠ Warning: No configuration file found at $CONFIG_FILE"
    echo "  Using default configuration values"
fi

# Allow environment variable overrides
CT_NAME="${JACKETT_CT_NAME:-$CT_NAME}"
NETWORK_MONITOR_SERVICE="${JACKETT_MONITOR_SERVICE:-$NETWORK_MONITOR_SERVICE}"
DESIRED_MAC_ADDRESS="${JACKETT_MAC_ADDRESS:-$DESIRED_MAC_ADDRESS}"
DHCP_CLIENT_ID="${JACKETT_DHCP_CLIENT_ID:-$DHCP_CLIENT_ID}"
DESIRED_STATIC_IP="${JACKETT_STATIC_IP:-$DESIRED_STATIC_IP}"
JACKETT_API_KEY="${JACKETT_API_KEY_OVERRIDE:-$JACKETT_API_KEY}"
JACKETT_STARTUP_DELAY="${JACKETT_STARTUP_DELAY_OVERRIDE:-$JACKETT_STARTUP_DELAY}"
JACKETT_ADDITIONAL_OPTIONS="${JACKETT_ADDITIONAL_OPTIONS_OVERRIDE:-$JACKETT_ADDITIONAL_OPTIONS}"

# Parse command line arguments for overrides
OVERRIDE_MAC_ADDRESS=""
OVERRIDE_ADDITIONAL_OPTIONS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --mac)
            OVERRIDE_MAC_ADDRESS="$2"
            shift 2
            ;;
        --mac=*)
            OVERRIDE_MAC_ADDRESS="${1#*=}"
            shift
            ;;
        --options)
            OVERRIDE_ADDITIONAL_OPTIONS="$2"
            shift 2
            ;;
        --options=*)
            OVERRIDE_ADDITIONAL_OPTIONS="${1#*=}"
            shift
            ;;
        *)
            # Keep other arguments for normal processing
            break
            ;;
    esac
done

# Apply overrides if provided
if [ -n "$OVERRIDE_MAC_ADDRESS" ]; then
    DESIRED_MAC_ADDRESS="$OVERRIDE_MAC_ADDRESS"
    echo "🔧 MAC address overridden via command line: $DESIRED_MAC_ADDRESS"
elif [ -n "${JACKETT_MAC_ADDRESS:-}" ]; then
    echo "🔧 MAC address overridden via environment: $DESIRED_MAC_ADDRESS"
elif [ -n "$DESIRED_MAC_ADDRESS" ]; then
    echo "📋 Using MAC address from configuration: $DESIRED_MAC_ADDRESS"
else
    echo "🔧 No custom MAC address configured - will use auto-generated"
fi

if [ -n "$OVERRIDE_ADDITIONAL_OPTIONS" ]; then
    JACKETT_ADDITIONAL_OPTIONS="$OVERRIDE_ADDITIONAL_OPTIONS"
    echo "🔧 Jackett additional options overridden via command line: $JACKETT_ADDITIONAL_OPTIONS"
elif [ -n "${JACKETT_ADDITIONAL_OPTIONS_OVERRIDE:-}" ]; then
    echo "🔧 Jackett additional options overridden via environment: $JACKETT_ADDITIONAL_OPTIONS"
elif [ -n "$JACKETT_ADDITIONAL_OPTIONS" ]; then
    echo "📋 Using Jackett additional options from configuration: $JACKETT_ADDITIONAL_OPTIONS"
else
    echo "📋 No additional Jackett options configured"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to show current network status
show_network_status() {
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                     JACKETT NETWORK STATUS                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Container status
    if lxc info "$CT_NAME" | grep -q "Status: Running"; then
        print_status "$GREEN" "📦 Container Status: RUNNING"
        CONTAINER_IP=$(lxc list "$CT_NAME" -c 4 --format csv | cut -d' ' -f1)
        if [ -n "$CONTAINER_IP" ]; then
            print_status "$GREEN" "🌐 Container IP: $CONTAINER_IP"
        else
            print_status "$RED" "🌐 Container IP: NOT ASSIGNED"
        fi
    else
        print_status "$RED" "📦 Container Status: NOT RUNNING"
        return 1
    fi
    
    # Current interface
    if [ -f "$CURRENT_INTERFACE_FILE" ]; then
        CURRENT_INTERFACE=$(cat "$CURRENT_INTERFACE_FILE")
        print_status "$BLUE" "🔗 Current Interface: $CURRENT_INTERFACE"
    else
        print_status "$YELLOW" "🔗 Current Interface: UNKNOWN"
    fi
    
    # Network monitor service status
    if systemctl is-active --quiet "$NETWORK_MONITOR_SERVICE"; then
        print_status "$GREEN" "👁️  Network Monitor: ACTIVE"
    else
        print_status "$RED" "👁️  Network Monitor: INACTIVE"
    fi
    
    # Interface availability
    echo ""
    print_status "$BLUE" "🔍 Interface Availability:"
    for interface in "${INTERFACE_PRIORITY_LIST[@]}"; do
        if [ -d "/sys/class/net/$interface" ]; then
            local status=$(cat "/sys/class/net/$interface/operstate" 2>/dev/null || echo "unknown")
            if [ "$status" = "up" ]; then
                # Test connectivity
                if timeout 3 ping -c 1 -I "$interface" 8.8.8.8 >/dev/null 2>&1; then
                    print_status "$GREEN" "   ✓ $interface: UP (Connected)"
                else
                    print_status "$YELLOW" "   ⚠ $interface: UP (No Internet)"
                fi
            else
                print_status "$RED" "   ✗ $interface: DOWN"
            fi
        else
            print_status "$RED" "   ✗ $interface: NOT FOUND"
        fi
    done
    
    # Jackett accessibility
    echo ""
    if [ -n "$CONTAINER_IP" ]; then
        print_status "$BLUE" "🔍 Testing Jackett accessibility..."
        print_status "$BLUE" "   Note: Testing from inside container due to macvlan isolation"
        
        # Test from inside container using localhost
        if lxc exec "$CT_NAME" -- timeout 10 curl -s --connect-timeout 5 "http://localhost:9117" >/dev/null 2>&1; then
            print_status "$GREEN" "🎯 Jackett Web Interface: ACCESSIBLE (tested from inside container)"
            
            # Test API endpoint from inside container
            if lxc exec "$CT_NAME" -- timeout 10 curl -s --connect-timeout 5 "http://localhost:9117/api/v2.0/server/config" >/dev/null 2>&1; then
                print_status "$GREEN" "🔧 Jackett API: ACCESSIBLE"
            else
                print_status "$YELLOW" "🔧 Jackett API: Web interface up, but API may be initializing"
            fi
            
            print_status "$GREEN" "📡 External Access: http://$CONTAINER_IP:9117 (from other devices)"
            print_status "$YELLOW" "📝 Note: Host cannot access container IP due to macvlan isolation"
        else
            print_status "$RED" "🎯 Jackett Service: NOT ACCESSIBLE inside container"
            print_status "$YELLOW" "   Try: lxc exec $CT_NAME -- systemctl status jackett"
        fi
    fi
    
    echo ""
}

# Function to show recent logs
show_logs() {
    local lines="${1:-20}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                    RECENT NETWORK MONITOR LOGS                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        tail -n "$lines" "$LOG_FILE"
    else
        print_status "$YELLOW" "No log file found at $LOG_FILE"
    fi
}

# Function to manually switch interface
manual_switch() {
    local target_interface="$1"
    
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                    MANUAL INTERFACE SWITCH                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Validate interface
    if [ ! -d "/sys/class/net/$target_interface" ]; then
        print_status "$RED" "✗ Interface $target_interface does not exist"
        return 1
    fi
    
    local status=$(cat "/sys/class/net/$target_interface/operstate" 2>/dev/null || echo "unknown")
    if [ "$status" != "up" ]; then
        print_status "$RED" "✗ Interface $target_interface is not up"
        return 1
    fi
    
    # Test connectivity
    if ! timeout 5 ping -c 1 -I "$target_interface" 8.8.8.8 >/dev/null 2>&1; then
        print_status "$YELLOW" "⚠ Warning: Interface $target_interface has no internet connectivity"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "$BLUE" "Operation cancelled"
            return 0
        fi
    fi
    
    print_status "$BLUE" "🔄 Switching container to interface: $target_interface"
    
    # Store current container state
    local container_running=false
    if lxc info "$CT_NAME" | grep -q "Status: Running"; then
        container_running=true
    fi
    
    # Update container network configuration
    lxc config device remove "$CT_NAME" eth0 2>/dev/null || true
    
    # Generate new MAC for new interface
    local mac_hash=$(echo -n "jackett-riscv-$(hostname)-$target_interface" | md5sum | cut -d' ' -f1)
    local container_mac
    if [ -n "$DESIRED_MAC_ADDRESS" ]; then
        container_mac="$DESIRED_MAC_ADDRESS"
        print_status "$BLUE" "Using custom MAC address: $container_mac"
    else
        container_mac=$(echo "$mac_hash" | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\).*/02:\1:\2:\3:\4:\5/')
        print_status "$BLUE" "Generated MAC address: $container_mac"
    fi
    
    lxc config device add "$CT_NAME" eth0 nic \
        nictype=macvlan \
        parent="$target_interface" \
        name=eth0 \
        hwaddr="$container_mac"
    
    # Restart container if it was running
    if $container_running; then
        print_status "$BLUE" "🔄 Restarting container..."
        lxc restart "$CT_NAME"
        sleep 10
        
        # Verify Jackett is accessible
        local container_ip=""
        print_status "$BLUE" "🔍 Waiting for container to get IP address..."
        for i in {1..30}; do
            container_ip=$(lxc list "$CT_NAME" -c 4 --format csv | cut -d' ' -f1)
            if [ -n "$container_ip" ]; then
                print_status "$GREEN" "✓ Container got IP: $container_ip"
                break
            fi
            sleep 2
        done
        
        if [ -n "$container_ip" ]; then
            print_status "$BLUE" "🔍 Testing Jackett accessibility..."
            print_status "$BLUE" "   Note: Testing from inside container due to macvlan isolation"
            
            for i in {1..20}; do
                # Test from inside container using localhost
                if lxc exec "$CT_NAME" -- timeout 10 curl -s --connect-timeout 5 "http://localhost:9117" >/dev/null 2>&1; then
                    print_status "$GREEN" "✓ Jackett web interface is accessible inside container"
                    
                    # Test API from inside container
                    if lxc exec "$CT_NAME" -- timeout 10 curl -s --connect-timeout 5 "http://localhost:9117/api/v2.0/server/config" >/dev/null 2>&1; then
                        print_status "$GREEN" "✓ Jackett API is responding correctly"
                    else
                        print_status "$YELLOW" "⚠ Jackett web interface is up but API may be initializing"
                    fi
                    
                                         print_status "$GREEN" "📡 External access available at: http://$container_ip:9117"
                     print_status "$YELLOW" "📝 Note: Host cannot access container IP due to macvlan isolation"
                     
                     echo "$target_interface" > "$CURRENT_INTERFACE_FILE"
                    return 0
                fi
                print_status "$BLUE" "Waiting for Jackett to be accessible... (attempt $i/20)"
                sleep 3
            done
            print_status "$RED" "✗ Jackett is not responding inside container after interface switch"
        else
            print_status "$RED" "✗ Container failed to get IP address"
        fi
    else
        echo "$target_interface" > "$CURRENT_INTERFACE_FILE"
        print_status "$GREEN" "✓ Interface switched successfully"
    fi
}

# Function to restart network monitor
restart_monitor() {
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                  RESTART NETWORK MONITOR                         ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    print_status "$BLUE" "🔄 Restarting network monitor service..."
    systemctl restart "$NETWORK_MONITOR_SERVICE"
    sleep 2
    
    if systemctl is-active --quiet "$NETWORK_MONITOR_SERVICE"; then
        print_status "$GREEN" "✓ Network monitor service restarted successfully"
    else
        print_status "$RED" "✗ Failed to restart network monitor service"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "Jackett Network Manager - Advanced Multi-Interface Network Management"
    echo ""
    echo "USAGE: $0 [--mac MAC_ADDRESS] [--options OPTIONS] [COMMAND] [OPTIONS]"
    echo ""
    echo "GLOBAL OPTIONS:"
    echo "  --mac MAC_ADDRESS         Override MAC address for interface switching"
    echo "  --mac=MAC_ADDRESS         (alternative format)"
    echo "  --options OPTIONS         Override Jackett additional command-line options"
    echo "  --options=OPTIONS         (alternative format)"
    echo ""
    echo "COMMANDS:"
    echo "  status                    Show current network status"
    echo "  logs [lines]              Show recent monitor logs (default: 20 lines)"
    echo "  switch <interface>        Manually switch to specified interface"
    echo "  restart-monitor           Restart the network monitoring service"
    echo "  list-interfaces           List all available network interfaces"
    echo "  test-interface <iface>    Test connectivity on specified interface"
    echo "  show-config               Display current configuration"
    echo "  help                      Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 status                              # Show current status"
    echo "  $0 logs 50                             # Show last 50 log entries"
    echo "  $0 switch end0                         # Switch to end0 interface"
    echo "  $0 --mac=02:16:E8:F8:95:41 switch end0 # Switch with custom MAC"
    echo "  $0 --options=\"--NoUpdates --DataFolder=/custom\" status # Custom Jackett options"
    echo "  $0 test-interface wlan0                # Test wlan0 connectivity"
    echo "  $0 show-config                         # Display configuration"
    echo ""
    echo "CONFIGURATION:"
    echo "  • Primary config: /etc/jackett-network.conf (created by build script)"
    echo "  • Environment overrides: JACKETT_MAC_ADDRESS, JACKETT_CT_NAME, etc."
    echo "  • Command line overrides: --mac option (highest priority)"
    echo ""
    echo "MACVLAN NETWORKING NOTES:"
    echo "  • Container uses macvlan networking for direct network access"
    echo "  • Host CANNOT ping or access container IP directly (by design)"
    echo "  • Other devices on network CAN access container normally"
    echo "  • This tool tests from inside container to avoid host isolation"
    echo "  • To test manually: lxc exec $CT_NAME -- curl http://localhost:9117"
    echo ""
}

# Function to list interfaces
list_interfaces() {
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                     AVAILABLE INTERFACES                         ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    for interface in /sys/class/net/*; do
        if [ -d "$interface" ]; then
            local iface_name=$(basename "$interface")
            # Skip loopback
            if [ "$iface_name" = "lo" ]; then
                continue
            fi
            
            local status=$(cat "$interface/operstate" 2>/dev/null || echo "unknown")
            local mac=$(cat "$interface/address" 2>/dev/null || echo "unknown")
            
            if [ "$status" = "up" ]; then
                # Test connectivity
                if timeout 3 ping -c 1 -I "$iface_name" 8.8.8.8 >/dev/null 2>&1; then
                    print_status "$GREEN" "✓ $iface_name: UP (Connected) - MAC: $mac"
                else
                    print_status "$YELLOW" "⚠ $iface_name: UP (No Internet) - MAC: $mac"
                fi
            else
                print_status "$RED" "✗ $iface_name: $status - MAC: $mac"
            fi
        fi
    done
    echo ""
}

# Function to test interface
test_interface() {
    local interface="$1"
    
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                      INTERFACE CONNECTIVITY TEST                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ ! -d "/sys/class/net/$interface" ]; then
        print_status "$RED" "✗ Interface $interface does not exist"
        return 1
    fi
    
    local status=$(cat "/sys/class/net/$interface/operstate" 2>/dev/null || echo "unknown")
    print_status "$BLUE" "Interface: $interface"
    print_status "$BLUE" "Status: $status"
    
    if [ "$status" != "up" ]; then
        print_status "$RED" "✗ Interface is not up"
        return 1
    fi
    
    print_status "$BLUE" "Testing connectivity..."
    local success_count=0
    
    for host in "${CONNECTIVITY_TEST_HOSTS[@]}"; do
        if timeout 5 ping -c 1 -I "$interface" "$host" >/dev/null 2>&1; then
            print_status "$GREEN" "✓ Successfully reached $host"
            ((success_count++))
        else
            print_status "$RED" "✗ Failed to reach $host"
        fi
    done
    
    if [ $success_count -gt 0 ]; then
        print_status "$GREEN" "✓ Interface $interface has internet connectivity ($success_count/${#CONNECTIVITY_TEST_HOSTS[@]} hosts reachable)"
    else
        print_status "$RED" "✗ Interface $interface has no internet connectivity"
    fi
    
    echo ""
}

# Function to show current configuration
show_config() {
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                      CURRENT CONFIGURATION                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    print_status "$BLUE" "📁 Configuration Source:"
    if [ -f "$CONFIG_FILE" ]; then
        print_status "$GREEN" "   ✓ Config file: $CONFIG_FILE"
        print_status "$BLUE" "   📅 Modified: $(stat -c %y "$CONFIG_FILE" 2>/dev/null | cut -d'.' -f1)"
    else
        print_status "$YELLOW" "   ⚠ Config file: NOT FOUND (using defaults)"
    fi
    echo ""
    
    print_status "$BLUE" "🐳 Container Configuration:"
    print_status "$BLUE" "   Container Name: $CT_NAME"
    print_status "$BLUE" "   Monitor Service: $NETWORK_MONITOR_SERVICE"
    echo ""
    
    print_status "$BLUE" "🌐 Network Configuration:"
    print_status "$BLUE" "   Interface Priority: ${INTERFACE_PRIORITY_LIST[*]}"
    if [ -n "$DESIRED_MAC_ADDRESS" ]; then
        print_status "$GREEN" "   MAC Address: $DESIRED_MAC_ADDRESS (custom)"
    else
        print_status "$YELLOW" "   MAC Address: Auto-generated"
    fi
    if [ -n "$DHCP_CLIENT_ID" ]; then
        print_status "$BLUE" "   DHCP Client ID: $DHCP_CLIENT_ID"
    else
        print_status "$YELLOW" "   DHCP Client ID: Not configured"
    fi
    if [ -n "$DESIRED_STATIC_IP" ]; then
        print_status "$BLUE" "   Requested Static IP: $DESIRED_STATIC_IP"
    else
        print_status "$BLUE" "   IP Assignment: Auto-assigned by DHCP"
    fi
    echo ""
    
    print_status "$BLUE" "🎛️ Jackett Configuration:"
    if [ -n "$JACKETT_API_KEY" ]; then
        print_status "$GREEN" "   API Key: Custom key configured"
    else
        print_status "$YELLOW" "   API Key: Auto-generated"
    fi
    print_status "$BLUE" "   Startup Delay: ${JACKETT_STARTUP_DELAY}s"
    if [ -n "$JACKETT_ADDITIONAL_OPTIONS" ]; then
        print_status "$GREEN" "   Additional Options: $JACKETT_ADDITIONAL_OPTIONS"
    else
        print_status "$YELLOW" "   Additional Options: None"
    fi
    echo ""
    
    print_status "$BLUE" "🔍 Connectivity Testing:"
    print_status "$BLUE" "   Test Hosts: ${CONNECTIVITY_TEST_HOSTS[*]}"
    if [ -n "${INTERFACE_CHECK_INTERVAL:-}" ]; then
        print_status "$BLUE" "   Check Interval: ${INTERFACE_CHECK_INTERVAL}s"
    fi
    echo ""
    
    print_status "$BLUE" "📁 File Paths:"
    print_status "$BLUE" "   Current Interface: $CURRENT_INTERFACE_FILE"
    print_status "$BLUE" "   Monitor Log: $LOG_FILE"
    if [ -n "${FAILOVER_SCRIPT:-}" ]; then
        print_status "$BLUE" "   Failover Script: $FAILOVER_SCRIPT"
    fi
    echo ""
    
    print_status "$BLUE" "🔧 Available Overrides:"
    print_status "$BLUE" "   Environment Variables:"
    print_status "$BLUE" "     JACKETT_MAC_ADDRESS             - Override MAC address"
    print_status "$BLUE" "     JACKETT_CT_NAME                 - Override container name"
    print_status "$BLUE" "     JACKETT_MONITOR_SERVICE         - Override monitor service name"
    print_status "$BLUE" "     JACKETT_DHCP_CLIENT_ID          - Override DHCP client ID"
    print_status "$BLUE" "     JACKETT_STATIC_IP               - Override static IP request"
    print_status "$BLUE" "     JACKETT_API_KEY_OVERRIDE        - Override API key"
    print_status "$BLUE" "     JACKETT_STARTUP_DELAY_OVERRIDE  - Override startup delay"
    print_status "$BLUE" "     JACKETT_ADDITIONAL_OPTIONS_OVERRIDE - Override additional options"
    print_status "$BLUE" "   Command Line:"
    print_status "$BLUE" "     --mac MAC_ADDRESS               - Override MAC address"
    print_status "$BLUE" "     --options OPTIONS               - Override Jackett additional options"
    echo ""
}

# Main execution
# Reset positional parameters after argument parsing
set -- "$@"

case "${1:-}" in
    "status")
        show_network_status
        ;;
    "logs")
        show_logs "${2:-20}"
        ;;
    "switch")
        if [ -z "${2:-}" ]; then
            print_status "$RED" "Error: Interface name required"
            echo "Usage: $0 [--mac MAC_ADDRESS] [--options OPTIONS] switch <interface>"
            exit 1
        fi
        manual_switch "$2"
        ;;
    "restart-monitor")
        restart_monitor
        ;;
    "list-interfaces")
        list_interfaces
        ;;
    "test-interface")
        if [ -z "${2:-}" ]; then
            print_status "$RED" "Error: Interface name required"
            echo "Usage: $0 test-interface <interface>"
            exit 1
        fi
        test_interface "$2"
        ;;
    "show-config")
        show_config
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        print_status "$RED" "Error: Unknown command '$1'"
        echo ""
        show_help
        exit 1
        ;;
esac 