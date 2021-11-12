#!/usr/bin/env bash

# https://docs.otc.t-systems.com/dns/index.html

(

[[ ! $CERTBOT_AUTH_OUTPUT =~ "$CERTBOT_VALIDATION" ]] && CERTBOT_AUTH_OUTPUT=''

BASE="$(cd "$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")" && pwd)" || \
  { echo "Couldn't determine the script's running directory." >&2; exit 1; }

OTCAUTH=$(pwd)/.otc-certbot-hook.auth
if [ ! -f "$OTCAUTH" ]; then
  OTCAUTH=${BASE}/.otc-certbot-hook.auth
fi
if [ ! -f "$OTCAUTH" ]; then
  >&2 echo "File $OTCAUTH not found."
  exit 2
fi
source "$OTCAUTH"
if [ ! "$(type -P curl)" ]; then
    >&2 echo "Install curl."
    exit 3
fi
if [ ! "$(type -P jq)" ]; then
    >&2 echo "Install jq."
    exit 4
fi
if [[ -z "$OTC_REGION" || -z "$OTC_USER" || -z "$OTC_PASSWORD" || \
      -z "$OTC_DOMAIN" || -z "$ROOT_ZONE" || -z "$OTC_IAM" || -z "$OTC_DNS" ]]; then
  >&2 echo "Variable missing. Check your $OTCAUTH settings."
  exit 5
fi
if [ -z "$CERTBOT_DOMAIN" ]; then
    [ -n "$CERTBOT_AUTH_OUTPUT" ] \
    && >&2 echo "Running through certbot? Call via: certbot --manual-cleanup-hook" \
    || >&2 echo "Running through certbot? Call via: certbot --manual-auth-hook"
    exit 6
fi

[ -n "$CERTBOT_AUTH_OUTPUT" ] \
&& echo "Deleting challenge ${CERTBOT_VALIDATION} ..." \
|| echo "Setting challenge ${CERTBOT_VALIDATION} ..."

# Request OTC access token
ACCESS_TOKEN=$(
cat <<EOT | jq -c . | \
  curl -is -X POST -H 'content-type: application/json' -d @- ${OTC_IAM}/auth/tokens | \
  grep '^X-Subject-Token:' | cut -f2 -d: | tr -d ' '
{ "auth": {
    "identity": {
      "password": {
        "user": {
          "name": "${OTC_USER}", 
          "password": "${OTC_PASSWORD}", 
          "domain": { "name": "${OTC_DOMAIN}" } } },
      "methods": [ "password" ] },
    "scope": { "project": { "name": "${OTC_REGION}" } } } }
EOT
)
if [ -z "${ACCESS_TOKEN}" ]; then
  >&2 echo "Unable to claim access to OTC. Check your $OTCAUTH settings."
  exit 10
fi
### echo ${ACCESS_TOKEN}

# Release OTC access token
function release_token {
  curl -Ss -X DELETE \
    -H "X-Auth-Token: ${ACCESS_TOKEN}" \
    -H "X-Subject-Token: ${ACCESS_TOKEN}" \
    ${OTC_IAM}/auth/tokens
}

# Querying {ROOT_ZONE}
ZONE_ID=$(curl -Ss -X GET -H "X-Auth-Token: ${ACCESS_TOKEN}" ${OTC_DNS}/zones | \
  jq -r '.zones[] | select(.name == "'${ROOT_ZONE}.'").id')
if [ -z "${ZONE_ID}" ]; then
    >&2 echo "Zone $ROOT_ZONE not found. Check your $OTCAUTH settings."
    release_token
    exit 11
fi
### echo ${ZONE_ID}

# Strip off any leading wildcard and prepend "_acme-challenge."
domain="_acme-challenge.${CERTBOT_DOMAIN#\*.}"
if [ "${domain}" = "${ROOT_ZONE}" ]; then
  subname=""
else
  subname="${domain%.$ROOT_ZONE}"
fi

# Querying ACME validation token(s) in {ROOT_ZONE}
JSON=$(curl -Ss -X GET -H "X-Auth-Token: ${ACCESS_TOKEN}" \
  ${OTC_DNS}/zones/${ZONE_ID}/recordsets?type=TXT\&name=${domain}. | jq -c .)
### echo ${JSON}

RRSET_ID=
ACME_TOKEN=
COUNT=$(echo $JSON | jq -r .metadata.total_count)
if [[ "$COUNT" == "0" ]]; then
  : # echo "No ACME validation token(s) found"
else
  RRSET_ID=$(echo $JSON | jq -r .recordsets[0].id)
  ACME_TOKEN=$(echo $JSON | jq -r .recordsets[0].records[])
fi

acme_tokens=()
for t in ${ACME_TOKEN}; do
  echo $t | grep -e ^\"${CERTBOT_VALIDATION}\"\$ >/dev/null
  if [[ $? == 0 ]]; then
    : # echo "ACME validation token found. Strip."
  else
    acme_tokens+=($t)
  fi
done

function json_request {
  echo '{"name":"'${domain}'","type":"TXT","ttl":300,"records":'$(echo $(IFS=, ; echo "${acme_tokens[*]}") | jq -cRn '(input | split(",")) as $t | [$t] | flatten')'}'
}

if [ -n "$CERTBOT_AUTH_OUTPUT" ]; then
  # Delete all occurrences of the current {CERTBOT_VALIDATION} from the rrset...
  # ...by delete the rrset or republish the remaining challenges.

  ### echo "DELETE validation ${CERTBOT_VALIDATION}:"
  if [[ ${#acme_tokens[@]} == 0 ]]; then
    if [ -z "${RRSET_ID}" ]; then
      >&2 echo "Ooops. There was no validation token(s) for ${domain}."
    else
      curl -Ss -X DELETE -H "X-Auth-Token: ${ACCESS_TOKEN}" \
        ${OTC_DNS}/zones/${ZONE_ID}/recordsets/${RRSET_ID} >/dev/null
    fi
   else
    json_request | curl -Ss -X PUT -d @- \
      -H 'content-type: application/json' -H "X-Auth-Token: ${ACCESS_TOKEN}" \
      ${OTC_DNS}/zones/${ZONE_ID}/recordsets >/dev/null
  fi
else
  # Add the current {CERTBOT_VALIDATION} to the rrset...
  # ...by add the rrset if empty or update the existing rrset.

  ### echo "ADD validation ${CERTBOT_VALIDATION}:"
  if [[ ${#acme_tokens[@]} == 0 ]]; then
    if [ -n "${RRSET_ID}" ]; then
      >&2 echo "Ooops. There was a validation token(s) for ${domain}."
    else
      acme_tokens+=(\"${CERTBOT_VALIDATION}\")
      json_request | curl -Ss -X POST -d @- \
        -H 'content-type: application/json' -H "X-Auth-Token: ${ACCESS_TOKEN}" \
        ${OTC_DNS}/zones/${ZONE_ID}/recordsets >/dev/null
    fi
  else
    acme_tokens+=(\"${CERTBOT_VALIDATION}\")
    json_request | curl -Ss -X PUT -d @- \
      -H 'content-type: application/json' -H "X-Auth-Token: ${ACCESS_TOKEN}" \
      ${OTC_DNS}/zones/${ZONE_ID}/recordsets >/dev/null
  fi
fi

release_token

[ -n "$CERTBOT_AUTH_OUTPUT" ] \
|| (echo "Waiting 60s for changes be published..."; date; sleep 60)

[ -n "$CERTBOT_AUTH_OUTPUT" ] \
&& echo -e '\e[32mChallenge deleted. Returning to certbot.\e[0m' \
|| echo -e '\e[32mChallenge published. Returning to certbot.\e[0m'

)
