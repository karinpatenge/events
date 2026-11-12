#!/usr/bin/env bash
# =============================================================================
# setup_iot.sh - creates the OCI IoT Platform side of the demo
#
# Author:      Karin Patenge
# Last update: 2026-11-03
#
#   2 digital twin models   PumpStation, Substation (DTDL v3, historized)
#   2 adapters              JSON payload -> model, endpoint /dh/telemetry
#   50 twin instances       10 pump stations + 40 substations (DIRECT, basic auth)
#   relationships "feeds"   pump station -> pump station / substation (optional)
#
# Output: data/twins_<city>.json and data/twins_<city>.sql (UPDATE dh_assets ...).
# The SQL file is only needed for the optional pull path (INGEST_MODE = IOT):
# the pull maps readings to assets by twin OCID. The database device simulation
# (06b_device_sim.sql) authenticates with the external key = asset id.
#
# Idempotent: every resource is looked up first (models and adapters by display
# name, twins by external key = asset id, relationships by source/target/content
# path) and only created if it does not exist. Re-running fills gaps and rewrites
# the two output files; nothing is created twice.
#
# Switching cities: the asset ids and the topology are the same for Vienna and
# Bucharest, only the names differ. The twins therefore stay the same; a run with
# the other city renames them (display name "PS-04 Pump station Rahova" instead of
# "PS-04 Pump station Favoriten"). Run it after @sql/00_install.sql <city> or
# @sql/test_all.sql <city>, so that the Console shows the city of the talk.
#
# Prerequisites:
#   - IoT domain group + IoT domain created (Console: Developer Services > Internet of Things)
#   - Vault secret with the device password (one secret shared by all demo twins)
#   - policy: Allow any-user to {SECRET_BUNDLE_READ, SECRET_READ} in compartment <c>
#             where ALL {request.principal.type = 'iotdomain', target.vault.id = '<vault-ocid>'}
#   - OCI CLI with the "iot" commands (OCI Cloud Shell works), jq
#
# Usage:
#   export IOT_DOMAIN_ID=ocid1.iotdomain....  DEVICE_SECRET_ID=ocid1.vaultsecret....
#   bash setup_iot.sh vie         # or: buc (bash: an upload from Windows drops the execute permission)
#   WITH_RELATIONSHIPS=1 bash setup_iot.sh vie
#
# Check flags of your CLI version first:  oci iot digital-twin-instance create --help
# =============================================================================
set -euo pipefail

CITY="${1:?usage: setup_iot.sh vie|buc}"
: "${IOT_DOMAIN_ID:?export IOT_DOMAIN_ID}"
: "${DEVICE_SECRET_ID:?export DEVICE_SECRET_ID}"
WITH_RELATIONSHIPS="${WITH_RELATIONSHIPS:-0}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NETWORK="$ROOT/data/network_${CITY}.json"
OUT_JSON="$ROOT/data/twins_${CITY}.json"
OUT_SQL="$ROOT/data/twins_${CITY}.sql"
[ -f "$NETWORK" ] || { echo "Missing $NETWORK - run scripts/python/generate_network.py --city ${CITY^^}"; exit 1; }

oci_iot() { oci iot "$@" --output json; }
# list results come as .data.items[] (newer CLI) or .data[] (older CLI)
items() { jq -c '(.data.items // .data // [])[]'; }

echo "== Domain"
oci_iot domain get --iot-domain-id "$IOT_DOMAIN_ID" | jq -r '.data | "device host: \(."device-host")"'

find_by_name() {   # $1 resource (digital-twin-model|digital-twin-adapter|digital-twin-instance), $2 display name
  oci_iot "$1" list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all 2>/dev/null |
    items | jq -r --arg n "$2" 'select(."display-name" == $n) | .id' | head -1
}

get_or_create_model() {   # $1 spec file, $2 display name
  local id; id=$(find_by_name digital-twin-model "$2")
  if [ -n "$id" ]; then echo "$id"; return; fi
  oci_iot digital-twin-model create --iot-domain-id "$IOT_DOMAIN_ID" \
      --display-name "$2" --spec "file://$1" --wait-for-state ACTIVE | jq -r '.data.id'
}
get_or_create_adapter() { # $1 model id, $2 adapter json (displayName inside)
  local name id; name=$(jq -r '.displayName' "$2"); id=$(find_by_name digital-twin-adapter "$name")
  if [ -n "$id" ]; then echo "$id"; return; fi
  oci_iot digital-twin-adapter create --iot-domain-id "$IOT_DOMAIN_ID" \
      --digital-twin-model-id "$1" --from-json "file://$2" --wait-for-state ACTIVE | jq -r '.data.id'
}

echo "== Models"
PS_MODEL=$(get_or_create_model "$HERE/model_pump_station.json" "DH PumpStation v1")
SS_MODEL=$(get_or_create_model "$HERE/model_substation.json"   "DH Substation v1")
echo "PumpStation model: $PS_MODEL"; echo "Substation model:  $SS_MODEL"

echo "== Adapters"
PS_ADAPTER=$(get_or_create_adapter "$PS_MODEL" "$HERE/adapter_pump_station.json")
SS_ADAPTER=$(get_or_create_adapter "$SS_MODEL" "$HERE/adapter_substation.json")
echo "PumpStation adapter: $PS_ADAPTER"; echo "Substation adapter:  $SS_ADAPTER"

echo "== Twin instances"
# existing twins by external key (= asset id): {"PS-04": {"id": "...", "name": "..."}, ...}
EXISTING=$(oci_iot digital-twin-instance list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all |
           items | jq -s 'map(select(."external-key" != null) | {key: ."external-key", value: {id: .id, name: ."display-name"}}) | from_entries')
TMP=$(mktemp)
jq -r '.assets[] | select(.asset_type=="PUMP_STATION" or .asset_type=="SUBSTATION") | "\(.asset_id)|\(.asset_type)|\(.name)"' "$NETWORK" |
while IFS='|' read -r ASSET TYPE NAME; do
  DISPLAY="$ASSET $NAME"
  TWIN=$(jq -r --arg k "$ASSET" '.[$k].id // empty' <<<"$EXISTING")
  CURRENT=$(jq -r --arg k "$ASSET" '.[$k].name // empty' <<<"$EXISTING")
  if [ -z "$TWIN" ]; then
    if [ "$TYPE" = "PUMP_STATION" ]; then MODEL=$PS_MODEL; ADAPTER=$PS_ADAPTER; else MODEL=$SS_MODEL; ADAPTER=$SS_ADAPTER; fi
    TWIN=$(oci_iot digital-twin-instance create --iot-domain-id "$IOT_DOMAIN_ID" \
             --display-name "$DISPLAY" --external-key "$ASSET" --auth-id "$DEVICE_SECRET_ID" \
             --digital-twin-model-id "$MODEL" --digital-twin-adapter-id "$ADAPTER" \
             --wait-for-state ACTIVE | jq -r '.data.id')
    echo "  created $ASSET -> $TWIN"
  elif [ "$CURRENT" != "$DISPLAY" ]; then
    oci_iot digital-twin-instance update --digital-twin-instance-id "$TWIN" \
        --display-name "$DISPLAY" --wait-for-state ACTIVE >/dev/null
    echo "  renamed $ASSET: $CURRENT -> $DISPLAY"
  else
    echo "  exists  $ASSET -> $TWIN"
  fi
  printf '{"asset_id":"%s","twin_ocid":"%s"}\n' "$ASSET" "$TWIN" >> "$TMP"
done
jq -s '.' "$TMP" > "$OUT_JSON"
{
  echo "-- Generated by scripts/iot/setup_iot.sh ($CITY) on $(date -u +%FT%TZ)"
  echo "-- Idempotent: sets the twin OCID per asset."
  jq -r '.[] | "UPDATE dh_assets SET twin_ocid = \u0027\(.twin_ocid)\u0027 WHERE asset_id = \u0027\(.asset_id)\u0027;"' "$OUT_JSON"
  echo "COMMIT;"
} > "$OUT_SQL"
rm -f "$TMP"

if [ "$WITH_RELATIONSHIPS" = "1" ]; then
  echo "== Relationships (feeds)"
  EXISTING_REL=$(oci_iot digital-twin-relationship list --iot-domain-id "$IOT_DOMAIN_ID" --lifecycle-state ACTIVE --all |
                 items | jq -r '"\(."source-digital-twin-instance-id")|\(."target-digital-twin-instance-id")|\(."content-path")"')
  # pipes from a pump station to a pump station or substation, open pipes only
  jq -r '.pipes[] | select(.valve_state=="OPEN") | select(.from_asset|startswith("PS-")) |
         select((.to_asset|startswith("PS-")) or (.to_asset|startswith("SS-"))) | "\(.from_asset)|\(.to_asset)"' "$NETWORK" |
  while IFS='|' read -r SRC DST; do
    S=$(jq -r --arg a "$SRC" '.[] | select(.asset_id==$a) | .twin_ocid' "$OUT_JSON")
    T=$(jq -r --arg a "$DST" '.[] | select(.asset_id==$a) | .twin_ocid' "$OUT_JSON")
    if grep -qxF "$S|$T|feeds" <<<"$EXISTING_REL"; then
      echo "  exists  $SRC -feeds-> $DST"
    else
      oci_iot digital-twin-relationship create --iot-domain-id "$IOT_DOMAIN_ID" \
          --source-digital-twin-instance-id "$S" --target-digital-twin-instance-id "$T" \
          --content-path feeds >/dev/null && echo "  created $SRC -feeds-> $DST"
    fi
  done
fi

echo "== Done. Optional (only for INGEST_MODE = IOT): load the twin mapping into the database:"
echo "   sql ogbemea2026@<db>_high @$OUT_SQL   (safe to re-run)"
