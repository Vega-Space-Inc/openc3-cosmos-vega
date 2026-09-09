# OpenC3 COSMOS Vega Plugin

Polls the Vega Space frontend API (`/api/v1/frontend/*` on
`admin.vega.space`) and surfaces satellite interference/coverage data as
COSMOS telemetry:

- `VEGA HEALTH` - API reachability (unauthenticated)
- `VEGA APPROVED_ORGS` - organizations your API key's user has approved
  access to (first-org snapshot) - use an id from here as `vega_org_id`
- `VEGA WORKSPACE` - satellites and ground stations for `vega_org_id`
  (first-record snapshots)
- `VEGA FORECASTING_SUMMARY` - interference/coverage forecast run status,
  plus the first satellite's most recent forecast day (max intensity,
  severity, event count)

All four packets are fetched once when `VEGA_INT` connects (so the CVT is
populated immediately) and then re-polled on two cadences via
`HttpClientInterface`:

- `vega_poll_period` (default 120 s) - `HEALTH` and `FORECASTING_SUMMARY`
- `vega_slow_poll_period` (default 3600 s) - `APPROVED_ORGS` and
  `WORKSPACE`, which change on the order of days

Set either to `0` to disable that periodic poll (the connect-time fetch still
runs). `WORKSPACE` and `FORECASTING_SUMMARY` only poll once `vega_org_id` is
set to a nonzero org id (see Setup). Request timeouts are `vega_read_timeout`
(default 30 s) and `vega_connect_timeout` (default 10 s).

Any non-2xx response from any command is routed to `VEGA ERROR_RESPONSE`
instead of the success packet: `HTTP_STATUS` carries the code (401 = bad or
missing key, 403 = no approved access to `vega_org_id`, 404 = unknown org or
no data in range, 429 = rate limited) and `BODY` the raw, unparsed response
(Vega returns HTML for some errors). `HTTP_STATUS` on every packet has limits
so anything outside 2xx shows red, `FORECASTING_SUMMARY RUN_STALE` shows
`OK` (green) / `STALE` (yellow), and `FIRST_SAT_DAY_MAX_SEVERITY` is coloured
low / medium / high. See `targets/VEGA/screens/status.txt` for a ready-made
screen, or add the items to Telemetry Grapher / Packet Viewer.

Decommutated command and telemetry records are retained for 30 days
(`CMD_DECOM_RETAIN_TIME` / `TLM_DECOM_RETAIN_TIME` in `plugin.txt`):
`WORKSPACE` and `FORECASTING_SUMMARY` carry whole JSON arrays on every poll,
so unbounded retention grows fast. Raise it in `plugin.txt` if you need more
history.

## Setup

This plugin authenticates with a **frontend API key** (`vgk_...` prefix,
scoped to one Vega user), not an account-level API token - the two are
different credential types and are not interchangeable.

The key is never part of the plugin configuration. It is stored as a COSMOS
secret and injected into the `Authorization` header by a write protocol
(`targets/VEGA/lib/api_key_protocol.rb`) after each command has been logged,
so it does not appear in plugin variables, command definitions, the command
log, or Command Sender.

1. Create a frontend API key in the Vega app under your account's API Keys
   page
2. In COSMOS open **Admin -> Secrets** and add a secret named `VEGA_API_KEY`
   whose value is that key (just the `vgk_...` string, no `Bearer ` prefix)
3. Install this plugin (see below) with `vega_org_id` left at its default
   (`0`). If the plugin was already installed before the secret existed,
   disconnect and reconnect `VEGA_INT` (or reinstall) so the interface
   container picks it up - a missing secret logs
   `VEGA_API_KEY not set - create it in Admin / Secrets and restart VEGA_INT`
   once and every authenticated request lands in `ERROR_RESPONSE` with
   `HTTP_STATUS` 401
4. Open the VEGA target's `Status` screen - `VEGA APPROVED_ORGS HTTP_STATUS`
   should read 200, and `FIRST_ORG_ID` / `FIRST_ORG_NAME` show one of your
   approved organizations. (Or run `GET /api/v1/frontend/organization_requests/approved_organizations`
   yourself to see the full list - a key's user can have several approved orgs.)
   `targets/VEGA/procedures/procedure.rb` does this check from Script Runner
   and then walks the status-screen alerts with injected telemetry.
5. Reinstall/reconfigure the plugin with `vega_org_id` set to the org id you
   want `WORKSPACE` and `FORECASTING_SUMMARY` to poll

To rotate the key, change the secret's value in Admin -> Secrets and
reconnect `VEGA_INT`; no plugin reinstall is needed. Revoke it in the Vega app
if this COSMOS instance is ever decommissioned.

## Extending

`WORKSPACE` and `FORECASTING_SUMMARY` currently expose a single "first
record" snapshot from each array in the response, since COSMOS telemetry
items are fixed-schema and `vega_org_id` only covers one org at a time. To
go further - multiple orgs at once, the full satellite/ground-station list,
per-day forecast history beyond the first day, or heatmap/track/position
endpoints (`forecasting/heatmap_slice`, `forecasting/track`,
`forecasting/satellite_position`) - either:

- add more `GET_*` commands / `KEY $.data.foo[N]...` items for specific
  indices or orgs you care about (duplicate the target with a different
  `vega_org_id` for multi-org polling), or
- write a small script (`targets/VEGA/procedures/`) that calls `cmd`/`tlm`
  in a loop and does something more dynamic, or
- build a custom Vue tool that calls the COSMOS API directly

## Getting Started

1. Edit the .gemspec file fields: name, summary, description, authors, email, and homepage
1. Update the LICENSE.md file with your company name

## Building non-tool / widget plugins

1. <Path to COSMOS installation>/openc3.sh cli rake build VERSION=X.Y.Z (or openc3.bat for Windows)
   - VERSION is required
   - gem file will be built locally

## Building tool / widget plugins using a local Ruby/Node/pnpm/Rake Environment

1. pnpm install --frozen-lockfile --ignore-scripts
1. rake build VERSION=1.0.0

## Building tool / widget plugins using Docker and the openc3-node container

If you don’t have a local node environment, you can use our openc3-node container to build custom tools and custom widgets

Mac / Linux:

```
docker run -it -v `pwd`:/openc3/local:z -w /openc3/local docker.io/openc3inc/openc3-node sh
```

Windows:

```
docker run -it -v %cd%:/openc3/local -w /openc3/local docker.io/openc3inc/openc3-node sh
```

1. pnpm install --frozen-lockfile --ignore-scripts
1. rake build VERSION=1.0.0

## Installing into OpenC3 COSMOS

1. Go to the OpenC3 Admin Tool, Plugins Tab
1. Click the install button and choose your plugin.gem file
1. Fill out plugin parameters
1. Click Install

## Contributing

We encourage you to contribute to OpenC3!

Contributing is easy.

1. Fork the project
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Before any contributions can be incorporated we do require all contributors to agree to a Contributor License Agreement

This protects both you and us and you retain full rights to any code you write.

## License

This OpenC3 plugin is released under the MIT License. See [LICENSE.md](LICENSE.md)
