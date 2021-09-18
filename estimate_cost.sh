#!/bin/bash
# Estimate the long-term cost of an Akash deployment, based on average block time and Akash exchange rate

cost="$1"

if [ -z "$cost" ]; then
  echo "Usage: $0 cost_in_uAKT" >&2
  exit 1
fi

last_price=$(
  timeout 15 curl -s "https://api-cloud.bitmart.com/spot/v1/ticker?symbol=AKT_USDT" \
    | jq -r ".data.tickers[0].last_price"
)
if [ -z "$last_price" ] || [ "$last_price" = "null" ]; then
  echo "Could not get last price from https://api-cloud.bitmart.com/spot/v1/ticker?symbol=AKT_USDT - assuming historical value of 5.3USDT"
  # snapshot taken 16 Sep 2021:
  last_price="5.3000"
fi
last_price_short=$(bc <<< "scale=2; $last_price / 1")

echo "Last AKT price: \$${last_price_short} USDT"

blocktime=$(
  timeout 15 curl -s "https://api.akash.aneka.io/stats" \
    | jq -r ".data.averageBlockTime"
)
if [ -z "$blocktime" ] || [ "$blocktime" = "null" ]; then
  echo "Could not get average block time from https://api.akash.aneka.io/stats - assuming historical value of 6.2s" >&2
  # snapshot taken 16 Sep 2021:
  blocktime="6.19862541725573"
fi
blocktime_short=$(bc <<< "scale=1; $blocktime / 1")

echo "Avg block time: ${blocktime_short}s"

akt_per_day_highprecision=$(bc <<< "scale=20; $cost / 1000000 / $blocktime * 86400")
# division by 1 is used to make bc's scale work correctly - it only works for division
akt_per_day=$(  bc <<< "scale=4; ($akt_per_day_highprecision) / 1")
akt_per_week=$( bc <<< "scale=4; ($akt_per_day_highprecision * 7) / 1")
akt_per_year=$( bc <<< "scale=4; ($akt_per_day_highprecision * 365) / 1")
akt_per_month=$(bc <<< "scale=4; ($akt_per_day_highprecision * 365 / 12) / 1")

price_per_day=$(  bc <<< "scale=2; ($akt_per_day   * $last_price) / 1")
price_per_week=$( bc <<< "scale=2; ($akt_per_week  * $last_price) / 1")
price_per_month=$(bc <<< "scale=2; ($akt_per_month * $last_price) / 1")
price_per_year=$( bc <<< "scale=2; ($akt_per_year  * $last_price) / 1")

echo
(
  echo "AKT"$'\t'"USDT"$'\t'"Timescale"
  echo "$akt_per_day"$'\t'"$price_per_day"$'\t'"per day"
  echo "$akt_per_week"$'\t'"$price_per_week"$'\t'"per week"
  echo "$akt_per_month"$'\t'"$price_per_month"$'\t'"per month"
  echo "$akt_per_year"$'\t'"$price_per_year"$'\t'"per year"
) | column -t -s$'\t'
