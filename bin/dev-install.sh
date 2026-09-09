#!/usr/bin/env bash
# Dev loop: build the plugin and load it into the local COSMOS compose stack.
#
#   bin/dev-install.sh            # version 0.47.0.<timestamp>, upgrades in place
#   bin/dev-install.sh 0.48.0     # explicit version (use for a real release)
#
# Then hard-refresh the browser (Cmd+Shift+R) - the widget JS is cached.
# One-time prerequisite: the VEGA_API_KEY secret must exist in Admin > Secrets
# BEFORE the first load, or every authenticated poll returns 401 and the
# widget shows its setup banner instead of data. `openc3cli load` auto-detects
# an installed openc3-cosmos-vega and upgrades it, keeping vars.json's values.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.47.0.$(date +%Y%m%d%H%M)}"
OP="${OPENC3_OPERATOR:-cosmos-openc3-operator-1}"
GEM="openc3-cosmos-vega-$VERSION.gem"

rake build VERSION="$VERSION"
docker cp "$GEM" "$OP:/tmp/$GEM"
docker cp vars.json "$OP:/tmp/vega-vars.json"
docker exec "$OP" openc3cli load "/tmp/$GEM" --variables /tmp/vega-vars.json
echo
echo "Loaded $GEM. Hard-refresh the browser (Cmd+Shift+R) to pick up the new widget."
