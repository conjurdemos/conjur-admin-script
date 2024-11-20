  echo '=========================================================================='
  hostname ; echo "START"
  ip ro | awk '{print }' | sort -u
  echo '=========================================================================='
  echo
  echo '## /etc/hosts' ; echo ; cat /etc/hosts ; echo
  echo '=========================================================================='
  echo '## /etc/hostname' ; echo ; cat /etc/hostname ; echo
  echo '=========================================================================='
  echo '## /etc/resolv.conf' ; echo ; cat /etc/resolv.conf ; echo
  echo '=========================================================================='
  echo '## uname -a' ; echo ; uname -a ; echo
  echo '=========================================================================='
  echo '## Selinux Status' ; echo ; sestatus ; echo
  echo '=========================================================================='
  echo '## Podman Version' ; echo ; podman version ; echo
  echo '=========================================================================='
  echo '## Filesystem Check' ; echo ; df -Ph /opt/cyberark/conjur ; echo
  echo '=========================================================================='
  echo '## Folder Permissions Check' ; echo ; ls -lrat /opt/cyberark/conjur ; echo
  echo '=========================================================================='
  # echo '## Conainer Appliance logs' ; echo ; podman logs  ; echo
  # echo '=========================================================================='
  echo '## Info Check' ; echo ; curl -s -k https://localhost/info ; echo
  echo '=========================================================================='
  echo '## Health Check' ; echo ; curl -s -k https://localhost/health ; echo
  echo '=========================================================================='
  hostname ; echo "END"
  echo '=========================================================================='
  echo
