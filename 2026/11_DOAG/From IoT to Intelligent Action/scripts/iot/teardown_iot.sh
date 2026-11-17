#!/usr/bin/env bash
# =============================================================================
# teardown_iot.sh - removes the digital twins of the demo from the OCI IoT Platform
#
# Author:      Karin Patenge
# Last update: 2026-11-13
#
# Removes what setup_iot.sh created, in this order:
#   1. relationships from or to a demo twin ("feeds")
#   2. the 50 twin instances (external key = asset id from data/network.json)
#   3. the 2 adapters and the 2 models of the demo
# and the local output files data/twins.json and data/twins.sql.
#
# Only demo resources are touched: twins whose external key is an asset id of
# data/network.json, adapters and models with the display names of setup_iot.sh.
# Other twins in the same IoT domain are kept. The IoT domain, the domain group
# and the Vault secret stay; delete them in the Console if no longer needed.
#
# Idempotent: what is already gone is skipped; a second run finds nothing to do.
# setup_iot.sh creates everything again.
#
# Before: stop the posts from the database, otherwise every tick fails with 401:
#   @sql/iot_publish.sql off
# After (only if you loaded data/twins.sql into the database):
#   UPDATE dh_assets SET twin_ocid = NULL WHERE twin_ocid IS NOT NULL; COMMIT;
#
# Usage (OCI Cloud Shell, from the repository root):
#   export IOT_DOMAIN_ID=ocid1.iotdomain....
#   bash scripts/iot/teardown_iot.sh         asks for confirmation
#   YES=1 bash scripts/iot/teardown_iot.sh   no confirmation
# =============================================================================
set -euo pipefail

: "${IOT_DOMAIN_ID:?export IOT_DOMAIN_ID}"
case "$IOT_DOMAIN_ID" in
  ocid1.iotdomain.*) ;;
  *) echo "IOT_DOMAIN_ID must be an IoT domain OCID (ocid1.iotdomain...), not $(cut -d. -f1-2 <<<"$IOT_DOMAIN_ID")..."; exit 1 ;;
esac
YES="${YES:-0}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NETWORK="$ROOT/data/network.json"
[ -f "$NETWORK" ] || { echo "Missing $NETWORK - upload data/network.json next to scripts/"; exit 1; }

oci_iot() { oci iot "$@" --output json; }
# list results come as .data.items[] (newer CLI) or .data[] (older CLI)
items() { jq -c '(.data.items // .data // [])[]'; }

wait_gone() {   # $1 resource (digital-twin-instance|...), $2 OCID: wait until DELETED or not found
  local state i
  for i in $(seq 1 60); do
    state=$(oci_iot "$1" get "--$1-id" "$2" 2>/dev/null | jq -r '.data."lifecycle-state"' || true)
    case "$state" in ""|DELETED) return 0 ;; esac
    sleep 5
  done
  echo "  $2 still $state after 5 minutes"; return 1
}

echo "== Domain"
oci_iot domain get --iot-domain-id "$IOT_DOMAIN_ID" | jq -r '.data | "\(."display-name") (\(."lifecycle-state"))"'

# demo twins: active instances whose external key is an asset id of the network
ASSETS=$(jq -c '[.assets[] | select(.asset_type=="PUMP_STATION" or .asset_type=="SUBSTATION") | .asset_id]' "$NETWORK")
TWINS=$(oci_iot digital-twin-instance list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all |
        items | jq -c --argjson a "$ASSETS" 'select(."external-key" as $k | $a | any(. == $k)) | {id: .id, key: ."external-key"}' |
        jq -s 'sort_by(.key)')
TWIN_IDS=$(jq -c '[.[].id]' <<<"$TWINS")
RELS=$(oci_iot digital-twin-relationship list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all |
       items | jq -c --argjson t "$TWIN_IDS" \
         'select((."source-digital-twin-instance-id" as $s | $t | any(. == $s)) or (."target-digital-twin-instance-id" as $d | $t | any(. == $d))) | .id' |
       jq -s '.')

N_TWINS=$(jq 'length' <<<"$TWINS"); N_RELS=$(jq 'length' <<<"$RELS")
echo "Found: $N_TWINS demo twins, $N_RELS relationships; adapters and models of the demo are removed too"

if [ "$YES" != "1" ]; then
  read -r -p "Delete them? This cannot be undone. Type yes: " ANSWER
  [ "$ANSWER" = "yes" ] || { echo "Nothing deleted."; exit 0; }
fi

echo "== Relationships"
for R in $(jq -r '.[]' <<<"$RELS"); do
  oci_iot digital-twin-relationship delete --digital-twin-relationship-id "$R" --force >/dev/null || echo "  FAILED $R"
done
for R in $(jq -r '.[]' <<<"$RELS"); do wait_gone digital-twin-relationship "$R"; done
echo "  deleted: $N_RELS"

echo "== Twin instances"
jq -r '.[] | "\(.key)|\(.id)"' <<<"$TWINS" |
while IFS='|' read -r KEY ID; do
  oci_iot digital-twin-instance delete --digital-twin-instance-id "$ID" --force >/dev/null \
    && echo "  deleted $KEY" || echo "  FAILED  $KEY"
done
[ "$N_TWINS" = "0" ] && echo "  none"

echo "== Waiting until the twins are gone (adapters and models are in use until then)"
for ID in $(jq -r '.[].id' <<<"$TWINS"); do wait_gone digital-twin-instance "$ID"; done

echo "== Adapters"
for F in "$HERE/adapter_pump_station.json" "$HERE/adapter_substation.json"; do
  NAME=$(jq -r '.displayName' "$F")
  for ID in $(oci_iot digital-twin-adapter list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all |
              items | jq -r --arg n "$NAME" 'select(."display-name" == $n) | .id'); do
    oci_iot digital-twin-adapter delete --digital-twin-adapter-id "$ID" --force >/dev/null
    wait_gone digital-twin-adapter "$ID" && echo "  deleted $NAME"
  done
done

echo "== Models"
for NAME in "DH PumpStation v1" "DH Substation v1"; do
  for ID in $(oci_iot digital-twin-model list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all |
              items | jq -r --arg n "$NAME" 'select(."display-name" == $n) | .id'); do
    oci_iot digital-twin-model delete --digital-twin-model-id "$ID" --force >/dev/null && echo "  deleted $NAME"
  done
done

rm -f "$ROOT/data/twins.json" "$ROOT/data/twins.sql"
echo "== Done. Recreate the twins with: WITH_RELATIONSHIPS=1 bash scripts/iot/setup_iot.sh"
echo "   If you loaded data/twins.sql into the database, also run there:"
echo "   UPDATE dh_assets SET twin_ocid = NULL WHERE twin_ocid IS NOT NULL; COMMIT;"
