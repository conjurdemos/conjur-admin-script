#!/bin/bash

# Common functions (used by different menu options)
# Function to prompt for user input with defaults from variable.sh
function get_user_input() {

  # Source the variable.sh file to load default values
  source ./variable.sh

  # Prompt for Conjur URL with default value
  read -p "Use default Conjur URL ($clusterDNS)? [y/n]: " use_default_conjururl
  if [[ "$use_default_conjururl" =~ ^[Yy]$ ]]; then
    conjururl=$clusterDNS
  else
    read -p "Enter Conjur Leader/HA Url (e.g., conjurvip.lab.net): " conjururl
  fi

  # Prompt for Conjur account with default value
  read -p "Use default Conjur Account ($accountName)? [y/n]: " use_default_account
  if [[ "$use_default_account" =~ ^[Yy]$ ]]; then
    account=$accountName
  else
    read -p "Enter Conjur Account (e.g., lab): " account
  fi

  # Prompt for username (no default)
  read -p "Enter username: " username

  # Prompt for password (no default, input is hidden)
  read -s -p "Please enter your password (input will be hidden): " password
  echo
}

function authenticate() {
# Fetch the token using the username and password
AUTHN_TOKEN=$(curl -s -k --user "$username:$password" https://"$conjururl"/authn/"$account"/login)
echo "Token retrieved successfully." ; echo

# Check if the token is empty
if [[ -z "$AUTHN_TOKEN" ]]; then
    echo "Error: No token received from the login request."
    exit 1
fi

# Get Authotization TOKEN (expires in 8 minutes)
TOKEN=$(curl -s -k --location --globoff "https://"$conjururl"/api/authn/"$account"/admin/authenticate" \
  --header "Accept-Encoding: base64" \
  --data "$AUTHN_TOKEN")

# Only for debugging
# echo "Authentication token: $TOKEN"
}

# FUNCTIONS INSIDE ADMIN MENU

function display_info() {
    echo "====================================="
    echo "Conjur Admin Script"
    echo "Release: Alpha v1"
    echo "====================================="
}

function collect_node_data() {
echo 
echo "[i] This script performs diagnostic checks on Conjur nodes to assist in troubleshooting."
echo "[i] It generates an output file containing the results of these checks."
echo "[i] The output file is used by the "Cluster Consistency Check" function."
echo
echo "  REQUIREMENTS:"
echo
echo   "[+] Netcat (nc) must be installed for network communication checks."
echo   "[+] Conjur appliance must be running on all three HA Cluster nodes: One leader and two standby nodes."
echo   "[+] This script ($0) and variable.sh should be located in the same directory."
echo   "[+] SSH access is required for all nodes, with the full path to the private key specified in variable.sh."
echo
read -p "    Enter the Conjur installation folder (default /opt/cyberark/conjur): Use default (y/n): " yesno
read -p "    Enter the username for accessing Conjur Linux servers (default conjur): Use default (y/n): " luser

echo ; echo > conjur_checker.log

case $yesno in
  y)
  conjfol='/opt/cyberark/conjur'
  ;;
  n)
  read -p "[i] Enter the custom Conjur installation folder: " conjfol
  ;;
  *)
  echo "Invalid Entry. Type: 'y' or 'n'"
  exit
  ;;
esac


case $luser in
  y)
  user='conjur'
  ;;
  n)
  read -p "[i] Enter the custom username for SSH Conjur Linux hosts: " user
  ;;
  *)
  echo "Invalid Entry. Type: 'y' or 'n'"
  exit
  ;;
esac

checknodes() {

# This is the script which is copied and executed in each of the nodes.
# Add or remove checks according your needs.

vipha=`grep -i clusterDNS variable.sh | awk -F"=" '{ print $2 } '`
leader=`grep -i masterDNS variable.sh | awk -F"=" '{ print $2 } '`
stand1=`grep -i standby1DNS variable.sh | awk -F"=" '{ print $2 } '`
stand2=`grep -i standby2DNS variable.sh | awk -F"=" '{ print $2 } '`
key=`grep -i privateKey variable.sh | awk -F"=" '{ print $2 } '`
folder=`pwd`

tee $folder/checker.sh <<EOF > /dev/null
  echo '=========================================================================='
  hostname ; echo "START"
  ip ro | awk '{print $9}' | sort -u
  echo '=========================================================================='
  echo
  echo '## /etc/hosts' ; echo ; cat /etc/hosts ; echo
  echo '=========================================================================='
  echo '## /etc/hostname' ; echo ; cat /etc/hostname ; echo
  echo '=========================================================================='
  echo '## /etc/resolv.conf' ; echo ; cat /etc/resolv.conf ; echo
  echo '=========================================================================='
  echo '## RedHat Release' ; echo ; cat /etc/redhat-release ; echo
  echo '=========================================================================='
  echo '## uname -a' ; echo ; uname -a ; echo
  echo '=========================================================================='
  echo '## Selinux Status' ; echo ; sestatus ; echo
  echo '=========================================================================='
  echo '## Podman Version' ; echo ; podman version ; echo
  echo '=========================================================================='
  echo '## Filesystem Check' ; echo ; df -Ph $conjfol ; echo
  echo '=========================================================================='
  echo '## Folder Permissions Check' ; echo ; ls -lrat $conjfol ; echo
  echo '=========================================================================='
  # echo '## Conainer Appliance logs' ; echo ; podman logs `podman ps | awk '{print $14}' | grep -v '^$'` ; echo
  # echo '=========================================================================='
  echo '## Info Check' ; echo ; curl -s -k https://localhost/info ; echo
  echo '=========================================================================='
  echo '## Health Check' ; echo ; curl -s -k https://localhost/health ; echo
  echo '=========================================================================='
  hostname ; echo "END"
  echo '=========================================================================='
  echo
EOF

for i in $vipha $leader $stand1 $stand2; do
  echo
  echo "==========================================================================" >> conjur_checker.log
  echo "Network Check on $i" >> conjur_checker.log
  
  ports_open=0  # Initialize a variable to track open ports

  for port in 5432 1999 443; do
    output=$(nc -zv "$i" "$port" 2>&1 | tee /dev/tty)
    echo "$output" | tee -a conjur_checker.log

    # Check if the output indicates that the port is open
    if [[ "$output" == *"Connected"* ]]; then
      ports_open=1  # Mark that at least one port is open
    fi
      # If no ports are open, exit the outer loop
    if [ $ports_open -eq 0 ]; then
    echo "No open ports found on $i. Exiting for this host." >> conjur_checker.log
    continue  # Skip to the next host
  fi
  done

  # Only copy and execute the script if there are open ports
  folder=$(pwd)
  cat $folder/checker.sh | ssh -i $key -l $user $i "cat > ~/checker.sh"
  ssh -i $key -l $user $i "chmod +x ~/checker.sh"
  ssh -i $key -l $user $i ~/checker.sh bash
done

}

echo
for i in container masterDNS clusterDNS standby1DNS standby2DNS accountName version privateKey
    do value=`grep -i $i variable.sh | grep '=' | awk -F"=" '{ print $2 } '`
    echo "[i] $i = $value"
    done
    echo "[i] Conjur Folder = $conjfol"
echo
read -p "Is everything correct? (y/n): " oknok

case $oknok in
  y)
  echo
  echo "[+] Running Network Checks..." ; echo
  checknodes >> conjur_checker.log
  echo ; echo "Done" ; echo
  echo "[i] Please find details in conjur_checker.log" ; echo
  ;;
  n)
  echo ; echo "[i] Please edit variable.sh file accordingly and run again" ; echo
  ;;
  *)
  echo "Invalid Entry. Type: 'y' or 'n'"
  exit
  ;;
esac

}

function cluster_consistency_check() {

BRED='\033[1;31m'
NC='\033[0m'
BGREEN='\033[1;32m'

# Check if the conjur_checker.log file exists
if [[ ! -e "conjur_checker.log" ]]; then
    echo -e "${BYELLOW} WARNING: File conjur_checker.log not found in `pwd`${NC}"
    echo -e "${BGREEN} Running first 2) Collect Data From Nodes.${NC}"
    collect_node_data
fi

# Function to parse node data
parse_node_data() {
    local node_data="$1"

    # Extract various parameters from the node data
    local node_name
    local release_version
    local podman_version
    local selinux_status
    local node_role
    local health_status

    node_name=$(echo "$node_data" | grep -m1 'Network Check on' | awk '{print $4}')
    release_version=$(echo "$node_data" | grep '"release"' | awk -F\" '{print $4}')
    podman_version=$(echo "$node_data" | grep -A3 '## Podman Version' | grep -m1 'Version:' | awk -F': ' '{print $2}' | sed 's/[[:space:]]\+/ /g')
    selinux_status=$(echo "$node_data" | grep -A2 '## Selinux Status' | grep 'SELinux status:' | awk '{print $3}')
    node_role=$(echo "$node_data" | grep -E '"role"|Node Role' | awk -F\" '{print $4}' | head -1)
    health_status=$(echo "$node_data" | grep '"degraded": true' | wc -l)
        
    # Return the parsed data in a structured format
    echo "$node_name|$release_version|$podman_version|$selinux_status|$node_role|$health_status"
}

# Function to compare parameters across all nodes
compare_health_status() {
    local roles=("$@")
    local master_count=0
    local standby_count=0

    # Count the number of master and standby roles
    for role in "${roles[@]}"; do
        if [[ "$role" == "master" ]]; then
            ((master_count++))
        elif [[ "$role" == "standby" ]]; then
            ((standby_count++))
        fi
    done

    # Check if there is at least one master and at least two standbys
    if [[ $master_count -ge 1 && $standby_count -ge 2 ]]; then
        echo "HA Cluster Status: OK (Healthy)"
    else
        echo "HA Cluster Status: NOK (Unhealthy)"
    fi
}

# Function to compare other parameters across all nodes
compare_parameters() {
    local parameter_name="$1"
    shift
    local values=("$@")

    # Check if all values are the same
    local first_value="${values[0]}"
    for value in "${values[@]}"; do
        if [[ "$value" != "$first_value" ]]; then
            echo "$parameter_name: NOK (Inconsistent)"
            return
        fi
    done
    echo "$parameter_name: OK (Consistent)"
}

# Main script writes here:
CONJUR_CHECKER_LOG="./conjur_checker.log"

# Check if the conjur_checker.log file exists
if [ ! -f "$CONJUR_CHECKER_LOG" ]; then
    echo "File $CONJUR_CHECKER_LOG not found. Please provide a valid file."
    exit 1
fi

# Array to store node information
node_info=()

# Read and parse the log file
current_node_data=""
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "END" ]]; then
        # Parse the current node data and store it in the array
        node_info+=("$(parse_node_data "$current_node_data")")
        current_node_data=""
    else
        current_node_data+="$line"$'\n'
    fi
done < "$CONJUR_CHECKER_LOG"

# If node_info array is empty, no data was found
if [ ${#node_info[@]} -eq 0 ]; then
    echo "No node data found in the file."
    exit 1
fi

# Separate the parsed data for comparison
declare -a node_names
declare -a release_versions
declare -a podman_versions
declare -a selinux_statuses
declare -a node_roles
declare -a health_statuses

for node in "${node_info[@]}"; do
    IFS='|' read -r node_name release_version podman_version selinux_status node_role health_status <<< "$node"
    node_names+=("$node_name")
    release_versions+=("$release_version")
    podman_versions+=("$podman_version")
    selinux_statuses+=("$selinux_status")
    node_roles+=("$node_role")
    health_statuses+=("$health_status")
done

# Output results of the consistency check
echo "Cluster Consistency Check Results:"
echo "==================================="
compare_parameters "Release Version" "${release_versions[@]}"
compare_parameters "Podman Version" "${podman_versions[@]}"
compare_parameters "SELinux Status" "${selinux_statuses[@]}"
compare_health_status "${node_roles[@]}"
echo "==================================="

# Show detailed node data
echo "Detailed Node Information:"
for node in "${node_info[@]}"; do
    IFS='|' read -r node_name release_version podman_version selinux_status node_role health_status <<< "$node"
    echo "-----------------------------------"
    echo "Node: $node_name"
    echo "Conjur Version: $release_version"
    echo "Podman Version: $podman_version"
    echo "SELinux Status: $selinux_status"
    echo "Node Role: $node_role"
    #echo "Health Status: $(if [ "$health_status" -gt 2 ]; then echo 'OK'; else echo 'Degraded'; fi)"
    echo "Health Status: $(if [ "$health_status" -eq 0 ]; then echo 'OK'; else echo 'Degraded'; fi)"
done

}

function export_policies() {

echo "This function exports Conjur Loaded policies, creating policy tree structure in folders"

# PREREQUISITES:

# 1- Conjur enterprise running version 13.4 or below.
# 2- Linux terminal with Conjur CLI version 8.0.1-2a14e75 or below:
# 3- Conjur administrative account logged in to Conjur with CLI `conjur login...`
# 4- Conjur valid administrative credentials for getting a valid token.

# Prompt user for input
get_user_input
authenticate

# Display input
echo "Using Conjur URL: $conjururl"
echo "Using Conjur Account: $account"
echo "Username: $username"


mkdir -p ~/policies_output
cd ~/policies_output
conjur list -k policy | awk -F ":"  ' { print $3 } ' | sed 's/..$//' > policies.out

# Create folder structure according current loaded policies and print them to policy.yaml files.

for i in `cat policies.out`
    do mkdir -p ~/policies_output/"$i"
    echo "[i] Extracting policy "$i""
    curl -s -k -X GET "https://"$conjururl"/policies/"$account"/policy/"$i"" -H "Authorization: Token token=\"$TOKEN\"" -H "Content-Type: application/x-yaml" > ~/policies_output/"$i"/policy.yaml
    echo "# conjur policy load -b `echo "$i" | sed 's/\/[^\/]*$//'` -f policy.yaml" | cat - ~/policies_output/"$i"/policy.yaml > temp && mv temp ~/policies_output/"$i"/policy.yaml
    echo "[+] Policy "$i" successful!" ; echo
done

echo "Export done, please check ~/policies_output/* folders"
 
}

function get_secrets_values() {

echo
echo -e "    WARNING: Output will show in Plain Text"
echo

# This script fetch Conjur secrets.

# PREREQUISITES:

# Access to Conjur API on port 443
# Conjur valid administrative credentials for getting a valid token.
# curl binary for the API call

# Prompt user for input
get_user_input
authenticate

# Export all variables for the logged in user:
conjur list -k variable  | awk -F ":" ' { print $3 } ' |  awk -F '"' ' { print $1 } ' >  variables.out

# Array of variable keys to fetch (modify this as needed)
# VARIABLE_KEYS=("username" "password")

# Iterate over the variable keys and fetch their values
for key in `cat variables.out`; do
    echo "Fetching secret value for: $key"

    # Fetch the secret value for the current key
    SECRET_VALUE=$(curl -s -k -H "Authorization: Token token=\"$TOKEN\"" \
    https://"$conjururl"/api/secrets/"$account"/variable/"$key")

    # Check if the secret value was successfully retrieved
    if [[ -z "$SECRET_VALUE" ]]; then
        echo "Error: No secret found for variable: $key"
    else
        echo "Value for $key: $SECRET_VALUE" ; echo
    fi

done

}

function get_objects_list() {

  echo "This function displays the total number of objects loaded in Conjur"
  
  # PREREQUISITES:

  # 1- Conjur enterprise running version 13.4 or below.
  # 2- Linux terminal with Conjur CLI version 8.0.1-2a14e75 or below:
  # 3- Conjur administrative account logged in to Conjur with CLI `conjur login...`
  # 4- Conjur valid administrative credentials for getting a valid token.

  # Prompt user for input
  get_user_input  # This will gather the values and set variables
  authenticate

  # Now you can use $conjururl, $account, $username, and $password in your script
  echo "Using Conjur URL: $conjururl"
  echo "Using Conjur Account: $account"
  echo "Username: $username"


# Api call for objects summary
curl -s -k -X GET "https://"$conjururl"/resources/"$account"" -H "Authorization: Token token=\"$TOKEN\"" -H "Content-Type: application/x-yaml" | jq '
    {
        Group: [.[] | select(.id | contains("group"))] | length,
        Host: [.[] | select(.id | contains("host"))] | length,
        Layer: [.[] | select(.id | contains("layer"))] | length,
        Policy: [.[] | select(.id | contains("policy"))] | length,
        User: [.[] | select(.id | contains("user"))] | length,
        Variable: [.[] | select(.id | contains("variable"))] | length,
        Webservice: [.[] | select(.id | contains("webservice"))] | length
    }
'
}

function variable_show() {
	get_user_input
	authenticate
	
	conjur list -k variable  | awk -F ":" ' { print $3 } ' |  awk -F '"' ' { print $1 } ' | sort -u >  variables.out
	
    local file="variables.out"

    # Check if the provided file exists
    if [[ ! -f "$file" ]]; then
        echo "File not found: $file"
        return 1
    fi

    # Read the lines into an array
    mapfile -t options < "$file"

    while true; do
        echo "Select an option (Press q or Q to exit):"
        select option in "${options[@]}"; do
            if [[ "$REPLY" =~ ^[Qq]$ ]]; then
                echo "Exiting the menu."
                return 0  # Exit the function
            elif [[ -n "$option" ]]; then
                echo "You selected: $option"
                break  # Exit the select loop
            else
                echo "Invalid selection. Try again."
            fi
        done

        # Prompt for action on selected option
        while true; do
            echo "Choose an action:"
            echo "1) Show secret value"
            echo "2) Show the resource info"
            echo "3) Return to variable list"
            read -p "Enter your choice (1, 2, or 3): " action

            case $action in
                1)
                    echo
                    echo "Showing secret value for: $option"
				    echo
					SECRET_VALUE=$(curl -s -k -H "Authorization: Token token=\"$TOKEN\"" https://"$conjururl"/api/secrets/"$account"/variable/"$option")
					# Check if the secret value was successfully retrieved
					if [[ -z "$SECRET_VALUE" ]]; then
						echo "Error: No secret found for variable: $option"
					else
						echo "Value for $option: $SECRET_VALUE" ; echo
					fi
					;;
                2)
					echo "Showing resource info for: $option"
					conjur resource show variable:$option
					;;
                3)
                    echo "Returning to variable list."
                    break  # Break the inner loop to return to the main menu
                    ;;
                *)
                    echo "Invalid choice. Please select 1, 2, or 3."
                    ;;
            esac
        done
    done
}


function grant_read_permissions() {
  
  get_user_input
  read -p "Input the host id to grant Read-only permissions to all objects: " readhost
  authenticate

# Create the host to grant read permissions to all objects:

while true; do
  read -p "WARNING: host and api_key will show in Plain Text when a new host is created. Agree? (y/n): " answer
  [[ "$answer" =~ ^[Yy]$ ]] && break
done

echo

output=$(curl -s -k -H "Content-Type: application/json" -H "Authorization: Token token=\"$TOKEN\"" -X POST --data $"- !host "$readhost"" "https://"$conjururl"/policies/"$account"/policy/root" && echo)

echo "$output"
echo "===================================================================================================================================================="
echo

if ! echo "$output" | grep -q "api_key"; then
  echo "WARNING: Host $readhost Already exists in Conjur. Processing permission grants." && echo
else
  while true; do
    read -p "Have you stored host ID and API key in a safe place? (y/n): " answer
    [[ "$answer" =~ ^[Yy]$ ]] && break
  done
fi

# Function to process entities and apply permissions
apply_permissions() {
    local entity_type=$1
    local policy_file="${entity_type}.out"

    # Export policies for the given entity type
    conjur list -k "$entity_type" | awk -F ":" '{
      for (i=3; i<=NF; i++) {
        if (i==3) {
          printf $i;
        } else {
          printf ":%s", $i;
        }
      }
      printf "\n";
    }' | sed 's/[",]//g' | grep -v '^$' > "$policy_file"

    # Apply read permissions
    while read -r resource; do
        # Skip empty or invalid IDs
        if [[ -z "$resource" || "$resource" =~ ^[[:space:]]*$ ]]; then
            echo "Skipping empty or invalid resource ID for $entity_type."
            continue
        fi

        # Ensure valid YAML structure
        yaml_payload="---
- !permit
  role: !host $readhost
  privileges: [read]
  resources: !${entity_type} \"$resource\""

        curl -s -k -X POST "https://$conjururl/policies/$account/policy/root" \
             -H "Authorization: Token token=\"$TOKEN\"" \
             -H "Content-Type: text/plain" \
             --data "$yaml_payload"

        echo "Applied read permission to $entity_type: $resource"
    done < "$policy_file"
}

# Create output directory for policies
output_dir=~/policies_output
mkdir -p "$output_dir"
cd "$output_dir" || exit 1

# Define entities to process
entities=("policy" "user" "host" "webservice" "layer" "group")

# Process each entity type
for entity in "${entities[@]}"; do
    echo "Processing $entity..."
    apply_permissions "$entity"
done

echo "Read-only permissions granted to host "$readhost". Temporary files stored in '$output_dir'."

}

function show_menu() {
	
# Define color codes
  BLUE='\033[1;34m'
  CYAN='\033[1;36m'
  BRED='\033[1;31m'
  BBLUE='\033[1;34m'
  NC='\033[0m' # No Color
    echo -e "${BBLUE}=====================================${NC}"	
    echo ""
    echo -e "${BBLUE} ┏┓    •      ┏┓ ┓   •    ┏┓   •    ${NC}"
    echo -e "${BBLUE} ┃ ┏┓┏┓┓┓┏┏┓  ┣┫┏┫┏┳┓┓┏┓  ┗┓┏┏┓┓┏┓╋ ${NC}"
    echo -e "${BBLUE} ┗┛┗┛┛┗┃┗┻┛   ┛┗┗┻┛┗┗┗┛┗  ┗┛┗┛ ┗┣┛┗ ${NC}"
    echo -e "${BBLUE}       ┛                        ┛   ${NC}"
    echo -e "${BBLUE}=====================================${NC}"	
    echo "1) Display Info"
    echo "2) Collect Data From Nodes"
    echo "3) Cluster Consistency Check"
    echo "4) Export the Effective Policy"
    echo "5) Fetch Secret Values in Bulk"
    echo "6) Conjur Objects List"
    echo "7) Conjur Variable Show"
    echo "8) Grant Read Permissions"
    echo "Q) Quit"
    echo "====================================="
}

# Main script logic
while true; do
    show_menu
    read -p "Select an option [1-7, N, Q]: " choice

    case $choice in
        1)
            display_info
            ;;
        2)
            collect_node_data
            ;;
        3)
            cluster_consistency_check
            ;;
        4)
            export_policies
            ;;
	5)
	    get_secrets_values
	    ;;
        6)
	    get_objects_list
	    ;;
        7)
            variable_show
            ;;
        8)
            grant_read_permissions
            ;;
        N|n)
            perform_action_n
            ;;
        Q|q)
            echo "Exiting the script. Have a nice day!"
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac

    echo ""
    read -p "Press [Enter] key to continue..."
done
