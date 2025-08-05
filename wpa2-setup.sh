#!/bin/bash

# Checking if script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

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

# Step 1: Kill Network Manager
airmon-ng check kill &> /dev/null
if [[ $? -ne 0 ]]; then
    error_exit "Failed to kill conflicting processes"
fi
    
echo "Killing Network Manager"

# Step 2: Configure Network Interface
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
systemctl enable networking > /dev/null 2>&1

# Step 3: Create WAP Configuration
apt install hostapd > /dev/null 2>&1
echo "Creating hostapd configuration..."
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
systemctl unmask hostapd > /dev/null 2>&1
systemctl enable hostapd > /dev/null 2>&1

# Step 4: Configure DNS and DHCP
apt install dnsmasq > /dev/null 2>&1
echo "Configuring dnsmasq..."
cat <<EOF > /etc/dnsmasq.conf
interface=$INTERFACE
dhcp-range=192.168.10.50,192.168.10.150,12h
dhcp-option=3,192.168.10.1
dhcp-option=6,8.8.8.8,8.8.4.4
EOF
systemctl enable dnsmasq > /dev/null 2>&1

# Step 5: Enable IPv4 Forwarding
echo "Enabling IPv4 forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf

# Step 6: Set NAT and Firewall Rules
echo "Setting up iptables rules..."
mkdir -p /etc/iptables > /dev/null 2>&1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE > /dev/null 2>&1
iptables -A FORWARD -i eth0 -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT > /dev/null 2>&1
iptables -A FORWARD -i $INTERFACE -o eth0 -j ACCEPT > /dev/null 2>&1
iptables-save > /etc/iptables/rules.v4 > /dev/null 2>&1

# Set DEBIAN_FRONTEND to noninteractive to auto-accept prompts
export DEBIAN_FRONTEND=noninteractive

# Install iptables-persistent without manual confirmation
apt-get install -y iptables-persistent > /dev/null 2>&1

# Reset DEBIAN_FRONTEND to its default value
unset DEBIAN_FRONTEND

# Step 7: Enable netfilter-persistent and Reboot
echo "Enabling netfilter-persistent..."
systemctl enable netfilter-persistent > /dev/null 2>&1

# Restart network services
systemctl restart networking > /dev/null 2>&1
systemctl restart netfilter-persistent > /dev/null 2>&1
systemctl restart dnsmasq > /dev/null 2>&1
systemctl restart hostapd > /dev/null 2>&1
sysctl net.ipv4.ip_forward=1 > /dev/null 2>&1

echo "Wireless access point setup complete"
