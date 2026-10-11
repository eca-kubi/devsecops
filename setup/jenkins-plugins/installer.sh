#!/bin/bash

set -eo pipefail

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"

# --- Fetch the CSRF crumb -----------------------------------------------
CRUMB_RESPONSE=$(curl -s --cookie-jar /tmp/cookies -u "${JENKINS_USER}:${JENKINS_PASS}" "${JENKINS_URL}/crumbIssuer/api/json")

if ! printf '%s' "$CRUMB_RESPONSE" | jq -e . >/dev/null 2>&1; then
  case "$CRUMB_RESPONSE" in
    *"401 Unauthorized"*)
      echo "ERROR: Jenkins rejected the credentials for user '${JENKINS_USER}' (HTTP 401)." >&2
      echo "       Retry with the real password, e.g. JENKINS_PASS='<password>' bash installer.sh" >&2 ;;
    *)
      echo "ERROR: Expected JSON from ${JENKINS_URL}/crumbIssuer/api/json but got:" >&2
      printf '%s\n' "$CRUMB_RESPONSE" >&2
      echo "HINT: Jenkins may still be starting, unreachable, or the credentials are wrong." >&2 ;;
  esac
  exit 1
fi

JENKINS_CRUMB=$(printf '%s' "$CRUMB_RESPONSE" | jq -r .crumb)

# --- Generate an API token ----------------------------------------------
TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Jenkins-Crumb:${JENKINS_CRUMB}" \
  --cookie /tmp/cookies \
  "${JENKINS_URL}/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken?newTokenName=demo-token66" \
  -u "${JENKINS_USER}:${JENKINS_PASS}")

if ! printf '%s' "$TOKEN_RESPONSE" | jq -e . >/dev/null 2>&1; then
  echo "ERROR: Could not generate an API token. Raw response:" >&2
  printf '%s\n' "$TOKEN_RESPONSE" >&2
  exit 1
fi

JENKINS_TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | jq -r .data.tokenValue)

echo $JENKINS_URL
echo $JENKINS_CRUMB
echo $JENKINS_TOKEN

while read -r plugin; do
   [ -z "$plugin" ] && continue
   echo "........Installing ${plugin} .."
   curl -s -X POST --data "<jenkins><install plugin='${plugin}' /></jenkins>" -H 'Content-Type: text/xml' "$JENKINS_URL/pluginManager/installNecessaryPlugins" --user "${JENKINS_USER}:$JENKINS_TOKEN"
done < plugins.txt


#### we also need to do a restart for some plugins

#### check all plugins installed in jenkins
# 
# http://<jenkins-url>/script

# Jenkins.instance.pluginManager.plugins.each{
#   plugin -> 
#     println ("${plugin.getDisplayName()} (${plugin.getShortName()}): ${plugin.getVersion()}")
# }


#### Check for updates/errors - http://<jenkins-url>/updateCenter
