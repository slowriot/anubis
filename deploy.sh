#!/bin/bash

AKASH_NET="https://raw.githubusercontent.com/ovrclk/net/master/mainnet"
scriptdir=$(dirname "${BASH_SOURCE[0]}")
deploy_file="$scriptdir/deploy.yaml"

fees="300uakt"
gaslimit="300000"

debug=${debug:-'false'}
dry_run=${dry_run:-'false'}
node_by_ping=${node_by_ping:-'false'}

if [ "$1" = "-y" ]; then
  ask_to_confirm=false
else
  ask_to_confirm=true
fi

script_dir="$(dirname "$0")"

version=$(akash version)
if [ "$?" != 0 ]; then
  echo "Could not query akash version - make sure akash is available on the path." >&2
  exit 1
fi
echo "Found akash version $version"

if [ -z "$(which yq)" ]; then
  echo "Missing dependency yq needed for parsing return data - install this with `pip install yq`" >&2
  exit 1
fi

if [ ! -f "$deploy_file" ]; then
  echo "Missing deploy manifest $deploy_file - cannot continue!" >&2
  exit 1
fi

# select a wallet to use
keys_list=$(akash keys list)
wallet_count=$(yq -r '. | length' <<< "$keys_list")
if [ "$wallet_count" = 0 ]; then
  echo "No akash wallets found - please create a wallet first.  See https://docs.akash.network/guides/wallet" >&2
  exit 1
elif [ "$wallet_count" = 1 ]; then
  # there is only one wallet, so select it without prompting
  wallet_selected=0
else
  # multiple wallets exist, so prompt the user which they want to use
  echo "Multiple wallets found:"
  for i in $(seq 0 "$((wallet_count - 1))"); do
    name=$(yq -r ".[$i].name" <<< "$keys_list")
    echo "$i: $name"
  done
  read -p "Enter number of wallet to use: " wallet_selected
fi
if [ -z "$wallet_selected" ]; then
  wallet_selected=0
fi
wallet_name=$(yq -r ".[$wallet_selected].name" <<< "$keys_list")
wallet_address=$(yq -r ".[$wallet_selected].address" <<< "$keys_list")
if [ -z "$wallet_address" ] || [ "$wallet_address" = "null" ]; then
  echo "Unable to find address of wallet $wallet_selected - check your wallet status with `akash keys list`" >&2
  exit 1
fi
echo "Using wallet $wallet_name, address $wallet_address"

# select a node for these transactions
nodes=$(curl -s "$AKASH_NET/rpc-nodes.txt")
if [ -z "$nodes" ]; then
  echo "Could not find node list at $AKASH_NET/rpc-nodes.txt!" >&2
  exit 1
fi

chain_id=$(curl -s "$AKASH_NET/chain-id.txt")
if [ -z "$chain_id" ]; then
  echo "Could not find node list at $AKASH_NET/chain-id.txt!" >&2
  exit 1
fi
echo "Chain ID: $chain_id"

node=$(head -1 <<< "$nodes")
if $node_by_ping; then
  lowest_ping=10000
  for rpc in $nodes; do
    hostname=$(cut -d '/' -f 3- <<< "$rpc" | cut -d ':' -f 1)
    ping=$(ping -c1 "$hostname" | grep ^rtt | cut -d '/' -f 5)
    if (( $(bc -l <<< "$ping < $lowest_ping") )); then
      lowest_ping="$ping"
      node="$rpc"
    fi
  done
  echo "Selected node $node with lowest ping ${lowest_ping}ms"
else
  echo "Selected default node $node"
fi

function akash_tx {
  # wrapper function to send a transaction
  $debug && echo "DEBUG: sending: akash tx $@ --from \"$wallet_address\" --node \"$node\" --chain-id \"$chain_id\" --fees \"$fees\" --broadcast-mode sync -y" >&2
  akash tx "$@" --from "$wallet_address" --node "$node" --chain-id "$chain_id" --fees "$fees" --gas "$gaslimit" --broadcast-mode sync -y
}
function akash_query {
  # wrapper function to query our orders, deployments etc
  $debug && echo "DEBUG: sending: akash query $@ --owner \"$wallet_address\" --node \"$node\"" >&2
  akash query "$@" --owner "$wallet_address" --node "$node"
}

echo "Getting count of past orders... "
order_result=$(akash_query market order list)
if [ -z "$order_result" ]; then
  echo "Empty result from akash query market order list.  Something is wrong with the remote RPC node." >&2
  exit 1
fi
orders_before=$(yq -r ".orders | length" <<< "$order_result")
if [ -z "$orders_before" ]; then
  echo "Error - no meaningful result from akash query market order list.  Result: $order_result" >&2
  exit 1
fi


echo "Requesting deployment... "
$dry_run || akash_tx deployment create "$deploy_file"

$dry_run || echo "Waiting 30 seconds for our order to propagate..."
$dry_run || sleep 30

echo "Looking for our new order..."
order_result=$(akash_query market order list)
while [ -z "$order_result" ]; do
  echo "Empty result from akash query market order list.  Something is wrong with the remote RPC node.  Retrying, to avoid losing our deployment..." >&2
  order_result=$(akash_query market order list)
done
orders=$(yq -r ".orders" <<< "$order_result")
if [ -z "$orders_before" ]; then
  echo "Error - no meaningful result from akash query market order list.  Result: $order_result" >&2
  exit 1
fi

orders_after=$(yq -r ". | length" <<< "$orders")
$dry_run || \
  if [ "$orders_after" -le "$orders_before" ]; then
    $dry_run || echo "Did not succeed in creating a new order ($orders_before orders before, and $orders_after after).  Check your balances." >&2
    $dry_run || exit 1
    $dry_run && echo "Did not find a new order - would normally exit, but this is dry run mode, so carrying on" >&2
  fi
new_order=$(yq -r ".[$((orders_after - 1))]" <<< "$orders")
if [ -z "$new_order" ]; then
  echo "Could not get the latest order - something has gone wrong.  Full order list: " >&2
  yq "." <<< "$orders" >&2
  exit 1
fi
dseq=$(yq -r ".order_id.dseq" <<< "$new_order")
gseq=$(yq -r ".order_id.gseq" <<< "$new_order")
oseq=$(yq -r ".order_id.oseq" <<< "$new_order")
if [ -z "$dseq" ]; then
  echo "Could not get dseq from new order - something has gone wrong.  Full order: " >&2
  yq "." <<< "$new_order" >&2
  exit 1
fi
echo "New order dseq $dseq gseq $gseq oseq $oseq"
echo "Verifying we can get this order..."
new_order=$(akash_query market order get --dseq "$dseq")
if [ -z "$new_order" ]; then
  echo "Could not get the order with dseq $dseq - something has gone wrong." >&2
  exit 1
fi
order_state=$(yq -r ".state" <<< "$new_order")
if [ "$order_state" = "open" ]; then
  echo "Order verified, open"
elif [ "$order_state" = "closed" ]; then
  $dry_run || echo "Order is closed - something has gone wrong." >&2
  $dry_run || exit 1
  $dry_run && echo "Order is closed - Would normally exit, but we are in dry run mode, so carrying on" >&2
else
  echo "Order state is \"$order_state\", but it should be \"open\" - trying to ignore and continue" >&2
fi
$dry_run || echo "Waiting 10 seconds for bids..."
$dry_run || sleep 10
echo "Checking for bids..."
bids=$(akash_query market bid list --dseq "$dseq" | yq -r ".bids")
num_bids=$(yq -r ". | length" <<< "$bids")
timeout=$(date +%s)
timeout=$((timeout + 60))
while [ -z "$bids" ] || [ "$num_bids" = "0" ]; do
  if [ "$(date +%s)" -gt "$timeout" ]; then
    echo "Did not receive any bids on this deployment within 60 seconds - requesting to cancel." >&2
    $dry_run || akash_tx deployment close --dseq "$dseq"
    echo "Deployment cancelled." >&2
    exit 1
  fi
  echo "Still no bids received, waiting another 10 seconds (up to a maximum of 60)..."
  sleep 10
  echo "Checking for bids..."
  bids=$(akash_query market bid list --dseq "$dseq" | yq -r ".bids")
  num_bids=$(yq -r ". | length" <<< "$bids")
done

echo "Received $num_bids bids."
cheapest=$(yq -r ".[0].bid.price.amount" <<< "$bids")
cheapest_denom="uakt"
for i in $(seq 0 "$((num_bids - 1))"); do
  provider=$(yq -r ".[$i].bid.bid_id.provider" <<< "$bids")
  price=$(yq -r ".[$i].bid.price.amount" <<< "$bids")
  denom=$(yq -r ".[$i].bid.price.denom" <<< "$bids")
  state=$(yq -r ".[$i].bid.state" <<< "$bids")
  if [ "$state" != "open" ]; then
    echo "WARNING: bid $i is not in open state ($state) - ignoring."
    $dry_run || continue
  fi
  if [ "$denom" != "uakt" ]; then
    echo "WARNING: received a bid in a denomination other than uakt, ignoring." >&2
    # if other denominations become common in use, update this script to convert and compare them equally
    continue
  fi
  if [ "$price" -lt "$cheapest" ]; then
    cheapest="$price"
    cheapest_denom="$denom"
  fi
  echo "Bid $i: $provider bids $price$denom"
done

echo "Cheapest price: $cheapest$cheapest_denom"
# build a list of providers offering this cheapest price
declare -a cheapest_providers
for i in $(seq 0 "$((num_bids - 1))"); do
  price=$(yq -r ".[$i].bid.price.amount" <<< "$bids")
  denom=$(yq -r ".[$i].bid.price.denom" <<< "$bids")
  state=$(yq -r ".[$i].bid.state" <<< "$bids")
  if [ "$state" != "open" ]; then
    $dry_run || continue
  fi
  if [ "$denom" != "uakt" ]; then
    # if other denominations become common in use, update this script to convert and compare them equally
    continue
  fi
  if [ "$price" != "$cheapest" ]; then
    continue
  fi
  provider=$(yq -r ".[$i].bid.bid_id.provider" <<< "$bids")
  cheapest_providers+=($provider)
done
if [ "${#cheapest_providers[@]}" == 1 ]; then
  provider="${cheapest_providers[0]}"
  echo "Cheapest provider: $provider"
else
  selected_provider=$((RANDOM % ${#cheapest_providers[@]}))
  provider="${cheapest_providers[$selected_provider]}"
  echo "Choosing at random from ${#cheapest_providers[@]} cheapest providers at the same price: $provider"
fi

echo "Price equivalent:"
"$script_dir"/estimate_cost.sh "$cheapest"

if $ask_to_confirm; then
  read -r -p "Would you like to accept this bid and deploy? [y/N] " response
  case "$response" in [yY][eE][sS]|[yY]) 
    echo "Bid acceptance manually confirmed."
    ;;
  *)
    echo "Will not accept this bid - cancelling deployment request."
    $dry_run || akash_tx deployment close --dseq "$dseq"
    $dry_run || echo "Deployment cancelled."
    exit
    ;;
  esac
fi

echo "Requesting lease for dseq $dseq..."
$dry_run || akash_tx market lease create --provider "$provider" --dseq "$dseq" --gseq "$gseq" --oseq "$oseq"

echo "Fetching lease info for dseq $dseq..."
leases=$(akash_query market lease list --dseq "$dseq" | yq -r ".leases")
num_leases=$(yq -r ". | length" <<< "$leases")
timeout=$(date +%s)
timeout=$((timeout + 60))
while [ "$num_leases" = 0 ]; do
  if [ "$(date +%s)" -gt "$timeout" ]; then
    echo "Could not find lease after timeout - closing deployment.  Full lease list for dseq $dseq:" >&2
    akash_query market lease list --dseq "$dseq" | yq "." >&2
    $dry_run || akash_tx deployment close --dseq "$dseq"
    exit 1
  fi
  echo "Still no lease visible for dseq $dseq, waiting another 10 seconds (up to a maximum of 60)..."
  sleep 10
  echo "Fetching lease info for dseq $dseq again..."
  leases=$(akash_query market lease list --dseq "$dseq" | yq -r ".leases")
  num_leases=$(yq -r ". | length" <<< "$leases")
done

# iterate through leases and find a valid one
lease_validated=false
for i in $(seq 0 "$((num_leases - 1))"); do
  echo "Verifying lease $((i + 1)) of $num_leases..."
  lease=$(yq -r ".[$i].lease" <<< "$leases")
  if [ -z "$lease" ] || [ "$lease" = "null" ]; then
    echo "WARNING: lease $i is not valid - skipping" >&2
    continue
  fi

  # confirm lease properties are as expected
  lease_state=$(yq -r ".state" <<< "$lease")
  lease_dseq=$(yq -r ".lease_id.dseq" <<< "$lease")
  lease_provider=$(yq -r ".lease_id.provider" <<< "$lease")
  if [ "$lease_dseq" = "$dseq" ] && [ "$lease_provider" = "$provider" ]; then
    echo "Found matching lease $i for dseq $dseq"
    if [ "$lease_state" != "active" ] && [ "$lease_state" != "open" ]; then
      $dry_run || echo "Lease state is \"$lease_state\" - lease should be \"active\" or \"open\", something is wrong, requesting to cancel.  Full lease info:" >&2
      $dry_run || yq "." <<< "$lease_state" >&2
      $dry_run || akash_tx deployment close --dseq "$dseq"
      $dry_run || echo "Deployment cancelled." >&2
      $dry_run || exit 1
      $dry_run && echo "Lease state is \"$lease_state\" instead of \"open\" - Would normally exit, but we are in dry run mode, so carrying on" >&2
    fi
    lease_validated=true
    break
  fi
done

if ! "$lease_validated"; then
  echo "Lease validation failed!  Did not find a matching open lease with dseq $dseq and provider $provider.  Requesting to cancel.  Full lease info:" >&2
  yq "." <<< "$leases" >&2
  $dry_run || akash_tx deployment close --dseq "$dseq"
  $dry_run || echo "Deployment cancelled." >&2
  $dry_run || exit 1
  $dry_run && echo "Would normally exit, but we are in dry run mode, so carrying on" >&2
fi

echo "Lease verified.  Sending manifest $deploy_file..."
$debug && echo "DEBUG: sending: akash provider send-manifest \"$deploy_file\" --dseq \"$dseq\" --provider \"$provider\" --from \"$wallet_address\" --node \"$node\""
$dry_run || akash provider send-manifest "$deploy_file" --dseq "$dseq" --provider "$provider" --from "$wallet_address" --node "$node"
if [ "$?" != 0 ]; then
  echo "Error sending manifest!  The provider did not accept it.  Retry manually or query the lease status:" >&2
  echo "  akash provider send-manifest \"$deploy_file\" --dseq \"$dseq\" --provider \"$provider\" --from \"$wallet_address\" --node \"$node\"" >&2
  echo "  akash provider lease-status --dseq \"$dseq\" --provider \"$provider\" --from \"$wallet_address\" --node \"$node\"" >&2
  exit 1
fi
echo "Manifest sent.  Querying lease status..."
$debug && echo "DEBUG: sending: akash provider lease-status --dseq \"$dseq\" --provider \"$provider\" --from \"$wallet_address\" --node \"$node\""
manifest_result=$(akash provider lease-status --dseq "$dseq" --provider "$provider" --from "$wallet_address" --node "$node")
yq "." <<< "$manifest_result"
host=$(yq -r ".forwarded_ports.web[0].host" <<< "$manifest_result")
port=$(yq -r ".forwarded_ports.web[0].externalPort" <<< "$manifest_result")
if [ -z "$host" ] || [ "$host" = "null" ]; then
  host=$(yq -r ".services.web.uris[0]" <<< "$manifest_result")
  port="80"
fi
if [ "$port" = "80" ]; then
  portstring=""
else
  portstring=":$port"
fi
echo
echo "Site is online, service URL:"
echo -e "http://\e[1;37m$host$portstring\e[0m"
echo
echo "View logs with:"
echo "  akash provider lease-logs --dseq \"$dseq\" --provider \"$provider\" --from \"$wallet_address\" --node \"$node\""
echo "  akash provider lease-events --dseq \"$dseq\" --provider \"$provider\" --from \"$wallet_address\" --node \"$node\""
echo
echo "When finished, you can quickly close the last launched deployment with ./close.sh"
