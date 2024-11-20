#!/bin/bash
# Conjur Fail Over Auto-Repair
# This script runs from bastion box, with ssh access to all the nodes.
# It checks conjur HA cluster status and repair if it is degraded to the initial state

# 1 - Load Variable file containing Conjur environment data and clean status.log file
source ./variable.sh


time=`/usr/bin/date '+%Y-%m-%d %T'`

# 2 Detect current state and decide next actions to take. Variables containing nodes FQDN will be taken from variable.sh file

# FUNCTIONS DEFINITION

detect_state() {
  echo > status.log
  for i in $masterDNS $standby1DNS $standby2DNS
    do
      # Determine current node roles
      echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Checking $i `curl -s -k https://$i/health | jq 'if .degraded == true and .role == "master" then "oldmaster" else "Not all conditions are met" end'`" >> status.log
      echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Checking $i `curl -s -k https://$i/health | jq 'if .degraded == false and .role == "master" then "newmaster" else "Not all conditions are met" end'`" >> status.log
      echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Checking $i `curl -s -k https://$i/health | jq 'if .degraded == false and .role == "standby" then "standby" else "Not all conditions are met" end'`" >> status.log

    done
}

detect_state

# Monitor if Failover Happens. Condition are met if we have one node promoted (newmaster), one standby (standby) and a degraded master (oldmaster).

while ! grep -q "newmaster" status.log || ! grep -q "standby" status.log || ! grep -q "oldmaster" status.log

do

  detect_state
  sleep 1  # Wait for 1 second before rechecking
  echo "`/usr/bin/date '+%Y-%m-%d %T'`" "No failover detected"

done

echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Failover detected!!!!"

# Prompt to proceed with recovery process
read -p "Do you want to proceed with the recovery process? (y/n): " proceed
if [[ "$proceed" =~ ^[Yy]$ ]]; then
  # Start recovery process
  echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Starting the recovery process..."

# Copy custom deploy_blank.sh

for i in $masterDNS $standby1DNS $standby2DNS
  do
    scp -i ~/fk deploy_blank.sh conjur@$i:/home/conjur/.
    ssh -i ~/fk -l conjur $i "chmod 0777 /home/conjur/deploy_blank.sh"
  done

echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Cluster degraded, identifying current node roles"
oldmaster=`grep oldmaster status.log | awk ' { print $4 } '`
newmaster=`grep newmaster status.log | awk ' { print $4 } '`
standby=`grep standby status.log | awk ' { print $4 } '`
echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Degraded Master = $oldmaster"
echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Promoted Master = $newmaster"
echo "`/usr/bin/date '+%Y-%m-%d %T'`" "Standby Node = $standby"

# Stop and remove Degraded Master and deploy a new blank container
    ssh -i ~/fk conjur@$oldmaster "podman stop conjur && podman rm conjur"
    ssh -i ~/fk conjur@$oldmaster "/home/conjur/deploy_blank.sh bash" >> log

# Create and upack seed from newmaster to oldleader and configure it as standby.
    ssh -i ~/fk conjur@$newmaster "podman exec conjur evoke seed standby $oldmaster $newmaster" | ssh -i ~/fk  conjur@$oldmaster "podman exec -i conjur evoke unpack seed -"
    ssh -i ~/fk conjur@$oldmaster "podman exec conjur evoke configure standby"

# Stop current leader $newmaster and redeploy a blank node
    ssh -i ~/fk conjur@$newmaster "podman stop conjur && podman rm conjur"
    ssh -i ~/fk conjur@$newmaster "/home/conjur/deploy_blank.sh bash" >> log

# Promote old Leader (currently standby) to master
    ssh -i ~/fk conjur@$oldmaster "podman exec conjur evoke role promote"

# Stop and remove Standby Node and recreate it
    ssh -i ~/fk conjur@$standby "podman stop conjur && podman rm conjur"
    ssh -i ~/fk conjur@$standby "/home/conjur/deploy_blank.sh bash" >> log

# Create seeds for standbys, unpack and configure.
    ssh -i ~/fk conjur@$oldmaster "podman exec conjur evoke seed standby $newmaster $oldmaster" | ssh -i ~/fk  conjur@$newmaster "podman exec -i conjur evoke unpack seed -"
    ssh -i ~/fk conjur@$oldmaster "podman exec conjur evoke seed standby $standby $oldmaster" | ssh -i ~/fk  conjur@$standby "podman exec -i conjur evoke unpack seed -"

    ssh -i ~/fk conjur@$newmaster "podman exec conjur evoke configure standby"
    ssh -i ~/fk conjur@$standby "podman exec conjur evoke configure standby"

# Enroll nodes

    ssh -i ~/fk conjur@$oldmaster "podman exec conjur evoke cluster enroll -n $oldmaster failover"
    ssh -i ~/fk conjur@$newmaster "podman exec conjur evoke cluster enroll -n $newmaster -m $oldmaster failover"
    ssh -i ~/fk conjur@$standby "podman exec conjur evoke cluster enroll -n $standby -m $oldmaster failover"

# Rebase follower Check why not running in conjurvip


    ssh -i ~/fk conjur@$follower1DNS "podman exec conjur evoke replication rebase $clusterDNS"
    ssh -i ~/fk conjur@$follower2DNS "podman exec conjur evoke replication rebase $clusterDNS"

    # 3 Run backup

    ssh -i ~/fk conjur@$oldmaster "podman exec conjur evoke backup"


    # 4 Unpack and restore





# OTHER SMALL FUNCTIONS

# 3 Stop container


# 4 Start Containers

# 5 Health Check

# Restore Backup
# podman exec conjur evoke unpack backup --key /opt/conjur/backup/key /opt/conjur/backup/2024-01-29T13-46-45Z.tar.xz.gpg
# podman exec conjur evoke restore --accept-eula

