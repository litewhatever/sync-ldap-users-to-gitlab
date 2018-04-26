#!/bin/bash

#
# This script :
# - creates LDAP users into Gitlab ;
#
# Prerequisites : use of ldapsearch from ldap-utils package

LDAP_URI="ldap://ldap.example.com"
LDAP_CONNECTION_OPTIONS="-xLLL -ZZ"
LDAP_BASE="dc=example,dc=com"
LDAP_BIND_DN="gitlabuser@example.com"
LDAP_BIND_PASSWORD="passw0rd"
LDAP_QUERY_FILTER="memberOf=CN=GitLab - Users,OU=Groups,DC=example,DC=com"
LDAP_QUERY_ATTRIBUTES="sAMAccountName cn mail"
LDAP_QUERY_RESULTS_FILE="/tmp/copy_users_from_ldap_to_gitlab.txt"

GITLAB_API_URL="http://localhost:8080/api/v4"
GITLAB_ADMIN_PRIVATE_TOKEN="ueP3rae4eix~a123512"

declare -A _gitlabUsersId=()

# Searches for gitlab user. If it does not exist, it creates it.
processUser() {
  local uid=$1
  local name=$2
  local mail=$3
  local password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 ; echo '')

  local response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" -XGET "$GITLAB_API_URL/users?username=$uid")

  if [[ "[]" == "$response" ]]; then
    # Creating Gitlab user
    echo "-> Creating Gitlab user username : $uid, e-mail : $mail, name : $name"
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ADMIN_PRIVATE_TOKEN" --data "username=$uid&email=$mail&name=$name&reset_password=false&skip_confirmation=true&password=$password" -XPOST "$GITLAB_API_URL/users")
    echo $response
  fi

  _gitlabUsersId[$uid]=$(echo $response | sed 's/\(.*\"id\":\)\([0-9]*\)\(,.*\)/\2/')
}

# Decode base64 strings
decode () {
  echo "$1" | base64 -d ; echo
}

echo "Process start time : $(date)"

# Sync LDAP users into Gitlab
# ---------------------------

ldapsearch $LDAP_CONNECTION_OPTIONS -H $LDAP_URI -b $LDAP_BASE -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD "$LDAP_QUERY_FILTER" $LDAP_QUERY_ATTRIBUTES > $LDAP_QUERY_RESULTS_FILE

REGEX_SAMACCOUNTNAME="sAMAccountName: (.*)"
REGEX_NAME="cn: (.*)"
REGEX_NAME_BASE64="cn:: (.*)"
REGEX_MAIL="mail: (.*)"

samaccountname=""
name=""
mail=""

while IFS= read -r line;
do

  if [[ "$line" =~ $REGEX_SAMACCOUNTNAME ]]; then
    samaccountname="$(echo "$line" | sed 's/sAMAccountName: \(.*\)/\1/')"
  fi

  if [[ "$line" =~ $REGEX_NAME ]]; then
    name="$(echo "$line" | sed 's/cn: \(.*\)/\1/')"
  elif [[ "$line" =~ $REGEX_NAME_BASE64 ]]; then
    name="$(decode $(echo "$line" | sed 's/cn:: \(.*\)/\1/'))"
  fi

  if [[ "$line" =~ $REGEX_MAIL ]]; then
    mail="$(echo "$line" | sed 's/mail: \(.*\)/\1/')"
  fi

  if [[ "$samaccountname" != "" && "$name" != "" && "$mail" != "" ]]; then
    processUser "$samaccountname" "$name" "$mail"
    samaccountname=""
    name=""
    mail=""
  fi

done < $LDAP_QUERY_RESULTS_FILE
