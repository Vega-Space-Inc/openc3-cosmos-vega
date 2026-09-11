#!/usr/bin/env bash
# Dev loop: build the plugin and load it into the local COSMOS compose stack.
# Loads through the cmd-tlm-api container as the owner of /gems: the operator
# mounts /gems read-only, and a plain `docker exec` runs as a user that does
# not own /gems/cosmoscache (EACCES). This is what Admin > Plugins does.
#
#   bin/dev-install.sh            # version 0.48.0.<timestamp>, upgrades in place
#   bin/dev-install.sh 0.48.0     # explicit version (use for a real release)
#
# Then hard-refresh the browser (Cmd+Shift+R) - the widget JS is cached.
# Optional: a VEGA_API_KEY secret in Admin > Secrets lets the background polls
# authenticate (without it they are dropped with one warning; the widget still
# works on the demo key or a key entered in the browser). `openc3cli load`
# auto-detects an installed openc3-cosmos-vega and upgrades it, keeping
# vars.json's values.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.48.0.$(date +%Y%m%d%H%M%S)}"
API="${OPENC3_API_CONTAINER:-cosmos-openc3-cosmos-cmd-tlm-api-1}"
OWNER="$(docker exec "$API" stat -c %u:%g /gems/cosmoscache)"
GEM="openc3-cosmos-vega-$VERSION.gem"

rake build VERSION="$VERSION"
docker cp "$GEM" "$API:/tmp/$GEM"
docker cp vars.json "$API:/tmp/vega-vars.json"
docker exec -u "$OWNER" "$API" openc3cli load "/tmp/$GEM" --variables /tmp/vega-vars.json
echo
echo "Loaded $GEM. Hard-refresh the browser (Cmd+Shift+R) to pick up the new widget."
