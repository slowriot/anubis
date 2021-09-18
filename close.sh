0#!/bin/bash

AKASH_NET="https://raw.githubusercontent.com/ovrclk/net/master/mainnet"

fees="300uakt"
gaslimit="300000"

debug=${debug:-'false'}
dry_run=${dry_run:-'false'}

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

echo "Looking for our latest order..."
orders=$(akash_query market order list | yq -r ".orders")
order_last=$(yq -r ". | length" <<< "$orders")
newest_order=$(yq -r ".[$((orders_after - 1))]" <<< "$orders")
if [ -z "$newest_order" ]; then
  echo "Could not get the latest order - something has gone wrong.  Full order list: " >&2
  yq "." <<< "$orders" >&2
  exit 1
fi

dseq=$(yq -r ".order_id.dseq" <<< "$newest_order")
if [ -z "$dseq" ]; then
  echo "Could not get dseq from new order - something has gone wrong.  Full order: " >&2
  yq "." <<< "$new_order" >&2
  exit 1
fi

echo "Requesting close of deployment..."
$dry_run || akash_tx deployment close --dseq "$dseq"
echo "Done."
