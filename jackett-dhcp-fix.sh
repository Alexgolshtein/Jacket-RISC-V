#!/usr/bin/env bash
set -euo pipefail

# Quick DHCP Fix for Jackett Container
echo "=== JACKETT DHCP QUICK FIX ==="

CT_NAME="dotnet-jackett"

echo "🔧 Checking container status..."
if ! lxc info "$CT_NAME" >/dev/null 2>&1; then
    echo "❌ Container $CT_NAME not found!"
    exit 1
fi

container_ip=$(lxc list "$CT_NAME" -c 4 --format csv | tr -d ' ')
echo "Current container IP: ${container_ip:-'NONE'}"

if [ -z "$container_ip" ] || [ "$container_ip" = "-" ]; then
    echo ""
    echo "❌ Container has no IP address - applying fixes..."
    
    echo ""
    echo "🔄 Fix 1: Restart DHCP client with unique ID..."
    unique_id="jackett-fix-$(hostname)-$(date +%s)"
    lxc exec "$CT_NAME" -- bash -c "
        echo 'Killing existing DHCP clients...'
        pkill dhclient || true
        sleep 2
        
        echo 'Clearing old leases...'
        rm -f /var/lib/dhcp/dhclient*.leases
        
        echo 'Bringing interface down and up...'
        ip link set eth0 down
        sleep 2
        ip link set eth0 up
        sleep 3
        
        echo 'Creating unique DHCP config...'
        cat > /tmp/dhclient-fix.conf << 'EOF'
send dhcp-client-identifier \"$unique_id\";
send host-name \"jackett-riscv-fix\";
request subnet-mask, broadcast-address, time-offset, routers,
        domain-name, domain-name-servers, domain-search, host-name,
        dhcp6.name-servers, dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,
        netbios-name-servers, netbios-scope, interface-mtu,
        rfc3442-classless-static-routes, ntp-servers;
EOF
        
        echo 'Requesting DHCP lease...'
        timeout 30 dhclient -cf /tmp/dhclient-fix.conf -v eth0
    " 2>&1
    
    sleep 5
    new_ip=$(lxc list "$CT_NAME" -c 4 --format csv | tr -d ' ')
    
    if [ -n "$new_ip" ] && [ "$new_ip" != "-" ]; then
        echo "✅ Fix 1 SUCCESS: Container now has IP $new_ip"
    else
        echo "❌ Fix 1 failed, trying Fix 2..."
        
        echo ""
        echo "🔄 Fix 2: Restart networking service..."
        lxc exec "$CT_NAME" -- systemctl restart networking
        sleep 10
        
        new_ip=$(lxc list "$CT_NAME" -c 4 --format csv | tr -d ' ')
        if [ -n "$new_ip" ] && [ "$new_ip" != "-" ]; then
            echo "✅ Fix 2 SUCCESS: Container now has IP $new_ip"
        else
            echo "❌ Fix 2 failed, trying Fix 3..."
            
            echo ""
            echo "🔄 Fix 3: Full container restart..."
            lxc restart "$CT_NAME"
            echo "Waiting 30 seconds for container to restart..."
            sleep 30
            
            new_ip=$(lxc list "$CT_NAME" -c 4 --format csv | tr -d ' ')
            if [ -n "$new_ip" ] && [ "$new_ip" != "-" ]; then
                echo "✅ Fix 3 SUCCESS: Container now has IP $new_ip"
            else
                echo "❌ All fixes failed!"
                echo ""
                echo "🔍 Manual troubleshooting needed:"
                echo "1. Check router DHCP logs"
                echo "2. Verify DHCP pool isn't exhausted"
                echo "3. Check for MAC address conflicts"
                echo "4. Run: ./jackett-network-debug.sh for detailed diagnostics"
                exit 1
            fi
        fi
    fi
    
    echo ""
    echo "🧪 Testing Jackett accessibility..."
    sleep 10  # Allow Jackett to start
    
    if lxc exec "$CT_NAME" -- curl -s --connect-timeout 10 "http://localhost:9117" >/dev/null 2>&1; then
        echo "✅ Jackett is accessible!"
        echo "🌐 Access Jackett at: http://$new_ip:9117"
    else
        echo "⚠️  IP obtained but Jackett not responding yet"
        echo "   Wait a few minutes and check: http://$new_ip:9117"
        echo "   Or check service: lxc exec $CT_NAME -- systemctl status jackett"
    fi
else
    echo "✅ Container already has IP: $container_ip"
    echo ""
    echo "🧪 Testing Jackett accessibility..."
    if lxc exec "$CT_NAME" -- curl -s --connect-timeout 10 "http://localhost:9117" >/dev/null 2>&1; then
        echo "✅ Jackett is accessible!"
        echo "🌐 Access Jackett at: http://$container_ip:9117"
    else
        echo "⚠️  Container has IP but Jackett not responding"
        echo "   Check service: lxc exec $CT_NAME -- systemctl status jackett"
    fi
fi

echo ""
echo "=== FIX COMPLETE ===" 