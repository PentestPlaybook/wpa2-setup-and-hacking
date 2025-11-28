#!/bin/bash
# Checking if script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Error handling function
error_exit() {
    echo "Error: $1"
    exit 1
}

# Check for internet connectivity
echo "Checking internet connectivity..."
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    error_exit "No internet connection. Please connect to the internet first (ethernet recommended)."
fi
echo "✓ Internet connection verified"

# Install packages FIRST while we have internet
echo "Installing required packages..."
apt update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y hostapd dnsmasq iptables-persistent > /dev/null 2>&1
if [ $? -ne 0 ]; then
    error_exit "Failed to install required packages."
fi
echo "✓ All packages installed"

# Detecting all the wireless interfaces
INTERFACES=$(iw dev | awk '/Interface/ {print $2}')

# Exit if no wireless interfaces are detected
if [ -z "$INTERFACES" ]; then
    echo "No wireless interfaces detected. Exiting."
    exit 1
fi

# Prompt for SSID and Passphrase
read -r -p "Enter SSID: " SSID
read -r -p "Enter Passphrase: " passphrase

# Display available wireless interfaces
echo "Available wireless interfaces:"
echo "$INTERFACES"

# Prompt the user to choose a wireless interface
read -r -p "Enter the wireless interface that will be used for the access point: " INTERFACE

# Validate that the chosen interface is in the list
if ! [[ $INTERFACES == *"$INTERFACE"* ]]; then
    error_exit "Invalid interface selected."
fi

echo "Wireless interface selected: $INTERFACE"

# Kill Network Manager NOW (after packages are installed)
echo "Killing conflicting processes..."
airmon-ng check kill &> /dev/null

# Configure Network Interface
echo "Configuring network interface..."
cat <<EOF > /etc/network/interfaces
source-directory /etc/network/interfaces.d
auto lo
iface lo inet loopback
allow-hotplug $INTERFACE
iface $INTERFACE inet static
address 192.168.10.1
netmask 255.255.255.0
EOF

# Create hostapd configuration
echo "Creating hostapd configuration..."
mkdir -p /etc/hostapd

cat <<EOF > /etc/hostapd/hostapd.conf
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$passphrase
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

systemctl unmask hostapd > /dev/null 2>&1
systemctl enable hostapd > /dev/null 2>&1

# Configure dnsmasq
echo "Configuring dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null

cat <<EOF > /etc/dnsmasq.conf
interface=$INTERFACE
dhcp-range=192.168.10.50,192.168.10.150,12h
dhcp-option=3,192.168.10.1
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
EOF

systemctl enable dnsmasq > /dev/null 2>&1

# Enable IPv4 Forwarding
echo "Enabling IPv4 forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipforward.conf
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

# Set NAT and Firewall Rules
echo "Setting up iptables rules..."
mkdir -p /etc/iptables > /dev/null 2>&1

iptables -F > /dev/null 2>&1
iptables -t nat -F > /dev/null 2>&1

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE > /dev/null 2>&1
iptables -A FORWARD -i eth0 -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT > /dev/null 2>&1
iptables -A FORWARD -i $INTERFACE -o eth0 -j ACCEPT > /dev/null 2>&1

iptables-save > /etc/iptables/rules.v4

systemctl enable netfilter-persistent > /dev/null 2>&1

# Configure the interface
echo "Bringing up network interface..."
rfkill unblock wifi > /dev/null 2>&1
ip link set $INTERFACE down 2> /dev/null
sleep 1
ip link set $INTERFACE up
ip addr flush dev $INTERFACE
ip addr add 192.168.10.1/24 dev $INTERFACE

# Start services
echo "Starting services..."

systemctl start netfilter-persistent > /dev/null 2>&1

echo -n "Starting dnsmasq... "
systemctl start dnsmasq > /dev/null 2>&1
sleep 2
systemctl is-active --quiet dnsmasq && echo "✓" || echo "✗"

echo -n "Starting hostapd... "
systemctl start hostapd > /dev/null 2>&1
sleep 2
systemctl is-active --quiet hostapd && echo "✓" || echo "✗"

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
systemctl is-active --quiet hostapd && echo "✓ hostapd running" || echo "✗ hostapd failed"
systemctl is-active --quiet dnsmasq && echo "✓ dnsmasq running" || echo "✗ dnsmasq failed"
echo ""
echo "SSID: $SSID"
echo "IP: 192.168.10.1"
