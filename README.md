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

`HEALTH` and `APPROVED_ORGS` are always polled. `WORKSPACE` and
`FORECASTING_SUMMARY` only poll once `vega_org_id` is set to a nonzero org
id (see Setup). All polling happens on an interval (`vega_poll_period`,
default 30s) via `HttpClientInterface`. See
`targets/VEGA/screens/status.txt` for a ready-made screen, or add the items
to Telemetry Grapher / Packet Viewer.

## Setup

This plugin authenticates with a **frontend API key** (`vgk_...` prefix,
scoped to one Vega user), not an account-level API token - the two are
different credential types and are not interchangeable.

1. Create a frontend API key in the Vega app under your account's API Keys
   page
2. Install this plugin (see below) with that key as `vega_api_token` and
   `vega_org_id` left at its default (`0`)
3. Open the VEGA target's `Status` screen - `VEGA APPROVED_ORGS HTTP_STATUS`
   should read 200, and `FIRST_ORG_ID` / `FIRST_ORG_NAME` show one of your
   approved organizations. (Or run `GET /api/v1/frontend/organization_requests/approved_organizations`
   yourself to see the full list - a key's user can have several approved orgs.)
4. Reinstall/reconfigure the plugin with `vega_org_id` set to the org id you
   want `WORKSPACE` and `FORECASTING_SUMMARY` to poll

**Note:** the key is stored as plain plugin config (visible to any COSMOS
admin, same as any other plugin variable) - not a hardened secrets-store
integration. Scope/rotate it in the Vega app accordingly.

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
