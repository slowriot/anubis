#!/bin/bash

project="$1"

api="http://127.0.0.1:17246/v1"
seeds="hyyqpngdoe4x4oto3emfdppbw7sj1pfaghbpmmhz5rqiuqg8uofmeo@seed.alt-clients.radicle.xyz:8776"

# remove this in prod:
export RAD_HOME="/dev/shm/radicle_temp"

if [ -z "$project" ]; then
  echo "Usage: $0 rad:git:project_urn" >&2
  exit 1
fi

if ! grep -q '^rad:git:' <<< "$project"; then
  echo "Project URN should be in the format rad:git:asdf1234" >&2
  exit 1
fi

# randomly generate a password
pass=$(apg -m16 -Mnlc -n1)

# bring up the radicle proxy in the background
radicle-proxy --default-seed "$seeds" &

# wait a moment for it to launch before we start sending requests
sleep 1

response=$(
  # create new keystore:
  curl -sv "$api/keystore" -X POST -H "Content-Type: application/json" -d "{\"passphrase\":\"$pass\"}" 2>&1
  
  # unseal existing keystore:
  #curl -sv "$api/keystore/unseal" -X POST -H "Content-Type: application/json" -d "{\"passphrase\":\"$pass\"}" 2>&1
)
cookie=$(grep '^< set-cookie: ' <<< "$response" | cut -d ' ' -f 3- | cut -d ';' -f 1)
if [ -z "$cookie" ]; then
  result=$(tail -n1 <<< "$response")
  echo "ERROR: Could not unseal Radicle keystore - cannot continue:"
  jq . <<< "$result" >&2 || echo "$result" >&2
  exit 1
fi

echo "Keystore created and unsealed successfully, auth cookie: $cookie"

# a brief wait is needed for the API to become ready
sleep 1

# create an identity
echo "Creating an identity:"
curl -s "$api/identities" -X POST -H "Content-Type: application/json" -d "{\"handle\":\"Anubis\"}" -b "$cookie" | jq .

echo
echo "Radicle identity:"
curl -s "$api/session" | jq .

echo
echo "Radicle requests:"
curl -s "$api/projects/requests" -b "$cookie" | jq .

echo
echo "Radicle tracked:"
curl -s "$api/projects/tracked" -b "$cookie" | jq .

echo
echo "Radicle failed:"
curl -s "$api/projects/failed" -b "$cookie" | jq .

echo
echo "Radicle contributed:"
curl -s "$api/projects/contributed" -b "$cookie" | jq .

echo
echo "Requesting to follow project $project..."
curl -s "$api/projects/requests/$project" -X PUT -b "$cookie" | jq .

#echo
#echo "notifications local peer events:"
#curl -v "$api/notifications/local_peer_events" -b "$cookie"


while true; do
  request_status=$(
    curl -s "$api/projects/requests" -b "$cookie" | jq -r ".[0].type"
  )
  if [ "$request_status" != "created" ] && [ "$request_status" != "cloning" ]; then
    break
  fi

  echo "Request status: $request_status, waiting..."
  sleep 1
done

if [ "$request_status" != "cloned" ]; then
  echo "ERROR: request status is \"$request_status\", was expecting \"cloned\".  Cannot continue.  Request info:" >&2
  curl -s "$api/projects/requests" -b "$cookie" | jq >&2
  exit 1
fi

echo "Repo $project cloned successfully - ready to extract."

# parse the project appropriately for git, format example: rad:git:hnrk8ueib11sen1g9n1xbt71qdns9n4gipw1o -> rad://hnrk8ueib11sen1g9n1xbt71qdns9n4gipw1o
project_git="rad://$(cut -d ':' -f 3- <<< "$project")"

# enable git credential helper, and add a credential to allow us to extract this
git config credential.helper 'store'
echo "rad://radicle:$pass@hnrk8ueib11sen1g9n1xbt71qdns9n4gipw1o.git" >> ~/.git-credentials
echo "DEBUG: verifying git credentials:"
ls -alh ~/.git-credentials
cat ~/.git-credentials

git clone --progress --verbose "$project_git" "target"
tree target
tree target/.git
ls -alh target
ls -alh target/.git/objects/*
