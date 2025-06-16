#!/usr/bin/env bash
set -euo pipefail

# Jackett Network Debug Script
# Use this to diagnose network issues after interface switching

echo "=== JACKETT NETWORK DEBUG REPORT ==="
echo "Generated: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Load configuration if available
CT_NAME="dotnet-jackett"
if [ -f "/etc/jackett-network.conf" ]; then
    echo "📋 Loading configuration from /etc/jackett-network.conf"
    source "/etc/jackett-network.conf"
else
    echo "⚠️  Configuration file not found, using defaults"
fi

echo ""
echo "🔧 CONTAINER STATUS:"
echo "   • Container Name: $CT_NAME"
if lxc info "$CT_NAME" >/dev/null 2>&1; then
    echo "   • Container Status: $(lxc list "$CT_NAME" -c s --format csv)"
    echo "   • Container IP: $(lxc list "$CT_NAME" -c 4 --format csv || echo "No IP assigned")"
else
    echo "   • Container Status: NOT FOUND"
    exit 1
fi

echo ""
echo "🌐 HOST NETWORK INTERFACES:"
echo "Available interfaces and their status:"
for interface in end0 end1 wlan0 eth0; do
    if [ -d "/sys/class/net/$interface" ]; then
        status=$(cat "/sys/class/net/$interface/operstate" 2>/dev/null || echo "unknown")
        mac=$(cat "/sys/class/net/$interface/address" 2>/dev/null || echo "unknown")
        echo "   • $interface: $status (MAC: $mac)"
        
        # Show IP info if interface is up
        if [ "$status" = "up" ]; then
            ip_info=$(ip addr show "$interface" 2>/dev/null | grep "inet " | awk '{print $2}' || echo "No IP")
            echo "     IP: $ip_info"
        fi
    else
        echo "   • $interface: NOT PRESENT"
    fi
done

echo ""
echo "📊 CURRENT INTERFACE STATUS:"
if [ -f "/tmp/jackett-current-interface" ]; then
    current_interface=$(cat "/tmp/jackett-current-interface")
    echo "   • Active Interface: $current_interface"
else
    echo "   • Active Interface: UNKNOWN (file not found)"
    current_interface="unknown"
fi

echo ""
echo "🔍 CONTAINER NETWORK CONFIGURATION:"
echo "Container network devices:"
lxc config device list "$CT_NAME" 2>/dev/null || echo "Could not list container devices"

echo ""
echo "Container network device details:"
lxc config device show "$CT_NAME" 2>/dev/null || echo "Could not show container device details"

echo ""
echo "📋 CONTAINER NETWORK STATUS:"
echo "Network interfaces inside container:"
lxc exec "$CT_NAME" -- ip addr show 2>/dev/null || echo "Could not get container network status"

echo ""
echo "Container routing table:"
lxc exec "$CT_NAME" -- ip route show 2>/dev/null || echo "Could not get container routing table"

echo ""
echo "📄 DHCP CLIENT STATUS:"
echo "DHCP client processes:"
lxc exec "$CT_NAME" -- ps aux | grep -E "(dhclient|dhcp)" | grep -v grep || echo "No DHCP client processes found"

echo ""
echo "DHCP client configuration:"
lxc exec "$CT_NAME" -- cat /etc/dhcp/dhclient.conf 2>/dev/null || echo "No dhclient.conf found"

echo ""
echo "DHCP leases:"
lxc exec "$CT_NAME" -- cat /var/lib/dhcp/dhclient.leases 2>/dev/null | tail -20 || echo "No DHCP leases found"

echo ""
echo "📊 NETWORK MONITOR LOGS (last 50 lines):"
tail -50 /var/log/jackett-network-monitor.log 2>/dev/null || echo "Monitor log not found"

echo ""
echo "🔧 SYSTEMD NETWORK SERVICES:"
echo "Network-related systemd services in container:"
lxc exec "$CT_NAME" -- systemctl status networking 2>/dev/null || echo "Networking service status unavailable"

echo ""
echo "Network manager status:"
lxc exec "$CT_NAME" -- systemctl status NetworkManager 2>/dev/null || echo "NetworkManager not available"

echo ""
echo "🧪 CONNECTIVITY TESTS:"
echo "Testing connectivity from container:"

# Test local network connectivity
echo "   • Ping gateway:"
lxc exec "$CT_NAME" -- bash -c '
    gateway=$(ip route | grep default | awk "{print \$3}" | head -1)
    if [ -n "$gateway" ]; then
        echo "     Gateway: $gateway"
        if ping -c 2 -W 3 "$gateway" >/dev/null 2>&1; then
            echo "     ✓ Gateway reachable"
        else
            echo "     ✗ Gateway NOT reachable"
        fi
    else
        echo "     ✗ No default gateway found"
    fi
' 2>/dev/null || echo "Could not test gateway connectivity"

# Test DNS resolution
echo "   • DNS resolution:"
lxc exec "$CT_NAME" -- nslookup google.com 2>/dev/null >/dev/null && echo "     ✓ DNS working" || echo "     ✗ DNS failing"

# Test internet connectivity
echo "   • Internet connectivity:"
lxc exec "$CT_NAME" -- ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1 && echo "     ✓ Internet reachable" || echo "     ✗ Internet NOT reachable"

echo ""
echo "🏃 SUGGESTED IMMEDIATE FIXES:"
echo ""

# Check if container has no IP
container_ip=$(lxc list "$CT_NAME" -c 4 --format csv | tr -d ' ')
if [ -z "$container_ip" ] || [ "$container_ip" = "-" ]; then
    echo "❌ ISSUE DETECTED: Container has no IP address"
    echo ""
    echo "🔧 IMMEDIATE FIX OPTIONS:"
    echo ""
    echo "1. RESTART DHCP CLIENT:"
    echo "   lxc exec $CT_NAME -- dhclient -r eth0  # Release current lease"
    echo "   lxc exec $CT_NAME -- dhclient eth0     # Request new lease"
    echo ""
    echo "2. RESTART NETWORKING:"
    echo "   lxc exec $CT_NAME -- systemctl restart networking"
    echo ""
    echo "3. RESTART CONTAINER:"
    echo "   lxc restart $CT_NAME"
    echo ""
    echo "4. MANUAL INTERFACE RESET:"
    echo "   lxc exec $CT_NAME -- ip link set eth0 down"
    echo "   lxc exec $CT_NAME -- ip link set eth0 up"
    echo "   lxc exec $CT_NAME -- dhclient eth0"
    echo ""
fi

# Check for MAC address issues
echo "5. CHECK FOR MAC ADDRESS CONFLICTS:"
container_mac=$(lxc config device get "$CT_NAME" eth0 hwaddr 2>/dev/null || echo "unknown")
echo "   Container MAC: $container_mac"
echo "   If same MAC appears on different interfaces, this can cause DHCP issues"
echo ""

echo "6. FORCE DHCP RENEWAL WITH NEW CLIENT ID:"
echo "   lxc exec $CT_NAME -- bash -c '"
echo "   dhclient -r eth0"
echo "   dhclient -i \"jackett-riscv-\$(hostname)-\$(date +%s)\" eth0"
echo "   '"
echo ""

echo "💡 DETAILED TROUBLESHOOTING:"
echo "   Run this script again after trying fixes to see if issues persist"
echo "   Check router DHCP logs for denied requests"
echo "   Verify DHCP pool has available addresses"
echo ""

echo "=== END DEBUG REPORT ===" 