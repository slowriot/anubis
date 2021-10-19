#!/bin/bash

project="$1"
target_dir="$2"

api="http://127.0.0.1:17246/v1"
seeds=${RADICLE_SEEDS:-hyncrnppok8iam6y5oemg4fkumj86mc4wsdiirp83z7tdxchk5dbn6@seed.upstream.radicle.xyz:8776}

# set an exit trap to clean up the radicle proxy when it's no longer required
function on_exit {
  echo "Cleaning up radicle-proxy on exit"
  kill $(pidof radicle-proxy)
}
trap on_exit EXIT

# for debugging:
#export RAD_HOME="/dev/shm/radicle_temp"
#export RUST_LOG=debug

if [ -z "$project" ]; then
  echo "Usage: $0 rad:git:project_urn target_dir" >&2
  exit 1
fi

if ! grep -q '^rad:git:' <<< "$project"; then
  echo "Project URN should be in the format rad:git:asdf1234" >&2
  exit 1
fi

pass=$(cat ~/.radicle_pass.txt)
if [ -z "$pass" ]; then
  # randomly generate a password if one doesn't already exist
  pass=$(apg -m16 -Mnlc -n1)
  echo "$pass" > ~/.radicle_pass.txt
fi

# bring up the radicle proxy in the background
echo "Starting Radicle proxy with default seeds $seeds..."
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
curl -s "$api/identities" -X POST -H "Content-Type: application/json" -d "{\"handle\":\"Anubis\"}" -b "$cookie" | jq -C .

echo
echo "Radicle identity:"
curl -s "$api/session" | jq -C .

echo
echo "Requesting to follow project $project..."
curl -s "$api/projects/requests/$project" -X PUT -b "$cookie" | jq -C .

while true; do
  request_status=$(
    curl -s "$api/projects/requests" -b "$cookie" | jq -r ".[0].type"
  )
  if [ "$request_status" != "created" ] && [ "$request_status" != "cloning" ] && [ "$request_status" != "requested" ] && [ "$request_status" != "found" ]; then
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

echo "Repo $project cloned successfully - ready to check out.  Finding peers:"

peers_result=$(curl -s "$api/projects/$project/peers" -b "$cookie")
jq -C . <<< "$peers_result"

peer_id=$(jq -r ".[1].peerId" <<< "$peers_result")
peer_handle=$(jq -r ".[1].status.user.metadata.handle" <<< "$peers_result")

echo "Attempting to check out from peer \"$peer_handle\" ($peer_id)..."
checkout_result=$(curl -s "$api/projects/$project/checkout" -X POST -H "Content-Type: application/json" -d "{\"path\":\"$target_dir\",\"peerId\":\"$peer_id\"}" -b "$cookie" | jq -r .)

echo "Checkout result: $checkout_result"

mv -v "$checkout_result" "$target_dir.tmp" && rm -vr "$target_dir" && mv -v "$target_dir.tmp" "$target_dir" || exit 1

echo "Checkout completed successfully to $target_dir"

cd "$target_dir"
git status

# save the password for this project in our git credentials
git config --global credential.helper store
git_url="rad://radicle:$pass@$(cut -d ':' -f 3- <<< "$project")"
echo "$git_url" >> ~/.git-credentials
echo "$git_url.git" >> ~/.git-credentials

exit 0
