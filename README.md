# Adjacent Satellite Interference Risk for OpenC3 COSMOS

*Powered by [Vega](https://vega.space).*

<p align="center">
  <img src="public/store_img.png" alt="Adjacent Satellite Interference Risk, powered by Vega" width="480">
</p>

OpenC3 COSMOS plugin that shows the adjacent satellite interference (ASI)
risk for your satellites and ground stations. It ships a Timeline widget
that draws each satellite's passes as a pass-by-band grid of predicted
interference, with measured history on request, and polls the
organization's satellites, ground stations and forecast status into COSMOS
telemetry. Forecasts and history come from the Vega interference
forecasting API.

## What you get

| Piece | Where |
|---|---|
| `GET_HEALTH`, `GET_DEMO_KEY`, `GET_APPROVED_ORGS`, `GET_WORKSPACE`, `GET_FORECASTING_SUMMARY`, `GET_DAY_DETAIL`, `GET_HISTORY` commands | `targets/VEGA/cmd_tlm/cmd.txt` |
| One response packet per command plus `ERROR_RESPONSE` (JSON decoded by `KEY` path) | `targets/VEGA/cmd_tlm/tlm.txt` |
| Timeline widget screen | `targets/VEGA/screens/forecast.txt` |
| COSMOS-native status screen | `targets/VEGA/screens/status.txt` |
| API key write protocol | `targets/VEGA/lib/api_key_protocol.rb` |
| HTTP client interface (stock plus a reconnect fix; stamps each response with its request path) | `targets/VEGA/lib/vega_http_client_interface.rb` |
| Smoke-test script | `targets/VEGA/procedures/procedure.rb` |
| Widget source (Vue 3 + Vuetify 3) | `src/` |

## Install

1. Build the gem (needs `node` and `pnpm` for the widget):

   ```bash
   pnpm install --frozen-lockfile --ignore-scripts
   rake build VERSION=1.0.0
   ```

   Or in the OpenC3 node container:

   ```bash
   docker run -it -v `pwd`:/openc3/local:z -w /openc3/local openc3inc/openc3-node sh
   /openc3/local $ pnpm install --frozen-lockfile --ignore-scripts && rake build VERSION=1.0.0
   ```

2. Install the `.gem` through **Admin → Plugins**. Leave `vega_org_id` at `0`
   for now.

3. Open the Timeline widget (Telemetry Viewer → `VEGA FORECAST`). It shows
   Vega's Demo Org straight away. To see your organization, create an API
   key at [app.vega.space](https://app.vega.space) (Settings → API keys)
   and add it in **Admin → Secrets** as `VEGA_API_KEY`. The widget picks it
   up on its next check (the refresh button, or **Connect your own data**
   → **Check again**); no restart.

4. Optional: reinstall with `vega_org_id` set to your organization's id (from
   `APPROVED_ORGS`) so the background polls and the status screen cover it.

### Plugin variables

| Variable | Default | Purpose |
|---|---|---|
| `vega_target_name` | `VEGA` | Target name. Change it to install the plugin more than once, e.g. one target per organization; the widget takes it as `TIMELINE <%= target_name %>` |
| `vega_hostname` | `admin.vega.space` | API hostname |
| `vega_port` | `443` | API port |
| `vega_protocol` | `https` | `http` or `https` |
| `vega_org_id` | `0` | Organization for the background polls; `0` skips them |
| `vega_poll_period` | `120` | Seconds between `GET_HEALTH` / `GET_FORECASTING_SUMMARY` polls; `0` disables |
| `vega_slow_poll_period` | `3600` | Seconds between `GET_APPROVED_ORGS` / `GET_WORKSPACE` polls; `0` disables |
| `vega_read_timeout` | `90.0` | Seconds to wait for a response |
| `vega_connect_timeout` | `10.0` | Seconds to wait for the connection |

The interface sends the four polled commands on connect (`OPTION CONNECT_CMD`)
so a fresh install has data immediately, then repeats them on the two cadences
above (`OPTION PERIODIC_CMD`). `GET_DEMO_KEY`, `GET_DAY_DETAIL` and
`GET_HISTORY` are sent by the widget as the user browses, never polled.

Any non-2xx reply lands in `ERROR_RESPONSE` with `HTTP_STATUS` and the raw
body: `401` bad or missing key, `404` organization unknown or not approved
for the key, `429` rate limited. No packet declares `LIMITS` on purpose; the
widget is the monitoring surface. Add them in your copy of `tlm.txt` if you
want COSMOS alarms.

## The API key

Vega uses **API keys** created in the app (`vgk_…`, read-only, scoped to the
organizations your user is approved for). See the
[API reference](https://docs.vega.space/api-reference/authentication).

The plugin uses **one key**: the `VEGA_API_KEY` secret in COSMOS
**Admin → Secrets**, which has its own permissions and audit trail. Nothing
in the plugin takes or stores a key. The write protocol reads the secret
when it sends each request, so the key never reaches a browser, a COSMOS log
or the packet stream, and an update in Admin → Secrets takes effect on the
next request with no restart. The `SECRET ENV` line mounts the same secret
as an environment variable, the fallback if the secret store cannot be read.

```
PROTOCOL WRITE api_key_protocol.rb Authorization VEGA_API_KEY "Bearer "
SECRET ENV VEGA_API_KEY VEGA_API_KEY
```

Without the secret every authenticated request goes out unauthenticated and
Vega answers `401` into `ERROR_RESPONSE` (one warning in the log), which the
status screen and the widget's onboarding both report; the widget falls back
to Vega's public demo key so a fresh install still shows data. That demo key
travels as the `OBFUSCATE`d `HTTP_HEADER_AUTHORIZATION` parameter, masked in
Command Sender and stripped from the packet by the protocol - the same
parameter lets a person send a command with a key of their own by hand.

### Limits and key lifetime

Each key may make 100 requests per minute
([rate limits](https://docs.vega.space/api-reference/rate-limits)). The
background polls and every widget on the instance share the one key's
budget. With the default variables the polls use about one request a
minute, and the widget paces its own requests, so the limit only matters
with many operators on one instance. A `429` lands in `ERROR_RESPONSE`.

Keys expire one year after creation and are revoked after 90 days unused
(the polls keep the shared secret in use, so the yearly expiry is the one to
plan for). An expired key shows as `401` in `ERROR_RESPONSE`, on the status
screen and in the widget: create a new key in the app and update the secret
in **Admin → Secrets**; it takes effect on the next request.

## Testing without waiting for real passes

`targets/VEGA/procedures/procedure.rb` checks the shared-secret path
(`GET_APPROVED_ORGS` must answer `200`), then injects `FORECASTING_SUMMARY`
values to walk `RUN_STALE` and `HTTP_STATUS` through nominal, stale and failed
so the status screen can be watched, and refetches the real packet at the end.
Run it from Script Runner. It hard-codes the `VEGA` target; edit its `TARGET`
constant if you renamed the target.

## Development

`bin/dev-install.sh` builds a timestamped gem and loads it into a local COSMOS
compose stack in place, reading plugin variables from `vars.json` (gitignored).
Hard-refresh the browser afterwards; the widget's settings menu shows the
build stamp so you can tell the new bundle loaded.

The widget builds against `@openc3/js-common` and `@openc3/vue-common` pinned
in `package.json`; keep them on the COSMOS minor you run and bump
`openc3_cosmos_minimum_version` in the gemspec with them. `sourcemap: true`
must stay on in `vite.config.js` (COSMOS copies the map at install).

To add an endpoint, copy an existing `COMMAND` and `TELEMETRY` pair: the four
derived HTTP parameters, `ACCESSOR HttpAccessor JsonAccessor`, `KEY` paths,
`HTTP_ERROR_PACKET` pointed at `ERROR_RESPONSE`, and `HTTP_HEADER_AUTHORIZATION`
with `OBFUSCATE` if it needs a key.

## License

See [LICENSE.md](LICENSE.md). Bundled third-party components are listed in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
