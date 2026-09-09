<!--
# Vega interference forecast timeline widget.
#
# User picks a satellite AND a ground station. One chart, continuous x axis
# (72 hours by default, click-drag to zoom into a narrower window),
# quantitative y axis ("Interference" = per-minute interferer count). Each
# frequency band gets its own lane of bottom-aligned slices, one per minute
# (or per few minutes when the lane is too narrow to show 1,440 distinct
# bars): slice height AND colour are the interferer count relative to that
# band's own peak, on a continuous green -> amber -> red ramp, so the chart
# reads like the Vega app's own timeline strip. Bands are toggled on/off via
# the chip row, and the ramp legend beside it says what the colours mean. A
# minute
# where the satellite isn't covered/visible from the ground station is
# plotted as zero interactions (not a gap). If the target has no
# working Vega connection yet, an onboarding state lets the user paste their
# own Vega frontend API key: it stays in that browser (localStorage) and is
# sent with each command as the OBFUSCATEd HTTP_HEADER_AUTHORIZATION
# parameter, which COSMOS masks in Command Sender and the text log and the
# interface protocol strips from the packet before the command logs are
# written. The VEGA_API_KEY COSMOS secret is only an optional fallback for
# the plugin's background polls.
# Driven by the VEGA COSMOS target's GET_DAY_DETAIL command / DAY_DETAIL
# telemetry, specifically the per-minute MINUTES_JSON breakdown (real
# per-band interference counts from admin.vega.space/api/v1/frontend/
# .../forecasting/day_detail).
-->

<template>
  <div class="timeline-widget" :style="computedStyle">
    <div v-if="notIntegrated" class="onboarding">
      <div class="onboarding-banner">
        <v-tooltip location="left" text="Re-check the Vega connection">
          <template #activator="{ props }">
            <button
              type="button"
              class="onboarding-refresh"
              :class="{ spinning: checkingIntegration }"
              :disabled="checkingIntegration"
              aria-label="Check the Vega connection again"
              v-bind="props"
              @click="retryIntegrationCheck"
            >
              <v-icon size="20">mdi-refresh</v-icon>
            </button>
          </template>
        </v-tooltip>

        <div class="onboarding-title">{{ integrationTitle }}</div>
        <div class="onboarding-body">
          {{ integrationMessage }}
        </div>

        <!-- The user's own Vega frontend API key. It is kept in this
             browser only (localStorage) and sent with each command as the
             OBFUSCATEd HTTP_HEADER_AUTHORIZATION parameter: COSMOS masks it
             in Command Sender and the text log, and the interface protocol
             strips it from the packet before the command logs are written.
             Nothing is stored server-side. -->
        <form
          v-if="showSetupSteps"
          class="onboarding-keyform"
          @submit.prevent="saveApiKey"
        >
          <label class="onboarding-keylabel" for="vega-api-key">
            Your Vega API key
          </label>
          <div class="onboarding-keyrow">
            <input
              id="vega-api-key"
              v-model="apiKeyInput"
              class="onboarding-input"
              type="password"
              placeholder="vgk_…"
              autocomplete="off"
              spellcheck="false"
              :disabled="savingKey"
            />
            <button
              type="submit"
              class="onboarding-save"
              :disabled="savingKey || !apiKeyInput.trim()"
            >
              {{ savingKey ? 'Checking…' : 'Connect' }}
            </button>
          </div>
          <div v-if="saveKeyError" class="onboarding-error">
            {{ saveKeyError }}
          </div>
          <div v-if="savedApiKey" class="onboarding-keystatus">
            A key ending in <code>{{ savedApiKeyTail }}</code> is saved in this
            browser.
            <button
              type="button"
              class="onboarding-forget"
              @click="forgetApiKey"
            >
              Forget it
            </button>
          </div>
          <div class="onboarding-keynote">
            Stays in this browser; COSMOS masks it in logs and never stores it.
            No key yet? Create a <em>frontend</em> API key (it starts with
            <code>vgk_</code>) at
            <a :href="VEGA_API_KEYS_URL" target="_blank" rel="noopener"
              >app.vega.space/settings/api-keys</a
            >.
          </div>
        </form>

        <div class="onboarding-actions">
          <a
            class="onboarding-cta"
            :href="VEGA_API_KEYS_URL"
            target="_blank"
            rel="noopener"
          >
            Get your API key →
          </a>
          <a
            class="onboarding-cta-ghost"
            :href="VEGA_SIGNUP_URL"
            target="_blank"
            rel="noopener"
          >
            Sign up →
          </a>
        </div>
        <div v-if="integrationCheckError" class="onboarding-error">
          {{ integrationCheckError }}
        </div>
      </div>
    </div>

    <template v-else>
      <div class="controls-col">
        <div class="controls-row">
          <v-select
            v-if="organizations.length > 1"
            v-model="selectedOrgId"
            :items="orgOptions"
            item-title="label"
            item-value="id"
            density="compact"
            hide-details
            variant="outlined"
            style="max-width: 260px"
            :disabled="loading || workspaceLoading"
          />
          <v-select
            v-model="selectedSatelliteId"
            :items="satelliteOptions"
            item-title="label"
            item-value="id"
            density="compact"
            hide-details
            variant="outlined"
            style="max-width: 280px"
            :disabled="loading || workspaceLoading"
          />
          <v-select
            v-model="selectedGroundStationId"
            :items="groundStationOptions"
            item-title="label"
            item-value="id"
            density="compact"
            hide-details
            variant="outlined"
            style="max-width: 220px"
            :disabled="loading || workspaceLoading"
          />
          <v-btn
            color="primary"
            variant="flat"
            style="height: 40px"
            :loading="loading"
            :disabled="
              workspaceLoading ||
              !selectedSatelliteId ||
              !selectedGroundStationId
            "
            @click="loadForecast(true)"
          >
            Refresh
          </v-btn>
          <v-menu>
            <template #activator="{ props }">
              <v-btn
                icon
                variant="text"
                style="height: 40px; width: 40px"
                v-bind="props"
              >
                <v-icon>mdi-cog</v-icon>
              </v-btn>
            </template>
            <v-list density="compact">
              <v-list-item
                :href="vegaHeatmapUrl"
                target="_blank"
                rel="noopener"
              >
                <v-list-item-title>View Heatmap</v-list-item-title>
              </v-list-item>
              <v-divider />
              <v-list-item
                :href="vegaGroundStationsUrl"
                target="_blank"
                rel="noopener"
              >
                <v-list-item-title>Edit Ground Stations</v-list-item-title>
              </v-list-item>
              <v-list-item
                :href="vegaSatellitesUrl"
                target="_blank"
                rel="noopener"
              >
                <v-list-item-title>Edit Satellites</v-list-item-title>
              </v-list-item>
              <v-list-item
                :href="VEGA_API_KEYS_URL"
                target="_blank"
                rel="noopener"
              >
                <v-list-item-title>API Settings</v-list-item-title>
              </v-list-item>
            </v-list>
          </v-menu>
        </div>

        <span v-if="TLM_OVERLAY_ENABLED" class="select-label"
          >SATELLITE TELEMETRY OVERLAY (COSMOS)</span
        >
        <div v-if="TLM_OVERLAY_ENABLED" class="controls-row">
          <v-select
            v-model="tlmTarget"
            :items="tlmTargets"
            label="Target"
            density="compact"
            hide-details
            variant="outlined"
            clearable
            style="max-width: 180px"
          />
          <v-select
            v-model="tlmPacket"
            :items="tlmPackets"
            label="Packet"
            density="compact"
            hide-details
            variant="outlined"
            clearable
            style="max-width: 220px"
            :disabled="!tlmTarget"
          />
          <v-select
            v-model="tlmItem"
            :items="tlmItems"
            label="Item"
            density="compact"
            hide-details
            variant="outlined"
            clearable
            style="max-width: 220px"
            :disabled="!tlmPacket"
          />
          <span v-if="tlmItem && !telemetryPoints.length" class="progress-text">
            Waiting for telemetry…
          </span>
          <span v-if="tlmError" class="error-text">{{ tlmError }}</span>
        </div>
      </div>

      <!-- Day picker: Yesterday / Today / Tomorrow shortcuts, plus a
           dropdown of every day on offer (30 days of measured history back,
           the 72h forecast forward), each tagged past / today / forecast.
           Reset zoom and the telemetry overlay toggle sit on the right. -->
      <div class="window-nav">
        <!-- Plain (variant="text") buttons so the COSMOS shell's outlined /
             filled button overrides don't apply; the container carries the
             same Astro field variables the v-selects above are drawn with. -->
        <v-btn-toggle v-model="quickDay" variant="text" class="quick-days">
          <v-btn :value="-1" :disabled="loading">Yesterday</v-btn>
          <v-btn :value="0" :disabled="loading">Today</v-btn>
          <v-btn :value="1" :disabled="loading">Tomorrow</v-btn>
        </v-btn-toggle>
        <!-- Calendar: a compact icon button opening a short list - the last
             four days and the next three - with today and the selected day
             marked and days past the forecast horizon greyed out. -->
        <v-menu location="bottom start">
          <template #activator="{ props }">
            <button
              type="button"
              class="cal-btn"
              :disabled="loading"
              v-bind="props"
              :title="`${days[0].weekday} ${days[0].display}`"
            >
              <v-icon size="18">mdi-calendar</v-icon>
              <span class="cal-btn-date">{{ days[0].display }}</span>
            </button>
          </template>
          <v-list density="compact" class="cal-list">
            <v-list-item
              v-for="d in calendarDays"
              :key="'cal-' + d.offset"
              :active="d.offset === windowOffsetDays"
              :disabled="d.disabled"
              @click="setWindowOffset(d.offset)"
            >
              <v-list-item-title>
                <span class="cal-weekday">{{ d.weekday }}</span>
                {{ d.display }}
              </v-list-item-title>
              <template #append>
                <span class="day-kind" :class="d.kind">{{ d.kindLabel }}</span>
              </template>
            </v-list-item>
          </v-list>
        </v-menu>
        <div class="window-nav-right">
          <!-- Loading / error text lives here: the box can shrink (min-width
               0, ellipsis) so a long message never widens the widget or
               adds a line -->
          <span
            v-if="workspaceLoading || loading || errorText"
            class="status-text"
            :class="{ 'error-text': !!errorText && !loading }"
            :title="errorText || progressText"
          >
            <template v-if="workspaceLoading">Loading workspace…</template>
            <template v-else-if="loading">{{ progressText }}</template>
            <template v-else>{{ errorText }}</template>
          </span>
          <button
            v-if="zoomRange"
            type="button"
            class="reset-zoom-btn"
            @click="resetZoom"
          >
            Reset zoom ({{ zoomSpanLabel }})
          </button>
          <button
            v-if="tlmItem"
            type="button"
            class="legend-chip"
            :class="{ inactive: !telemetryVisible }"
            @click="telemetryVisible = !telemetryVisible"
          >
            <svg class="chip-swatch" width="22" height="10" viewBox="0 0 22 10">
              <line
                x1="1"
                y1="5"
                x2="21"
                y2="5"
                :stroke="TLM_COLOR"
                stroke-width="2"
              />
            </svg>
            {{ tlmTarget }} {{ tlmItem }}
          </button>
        </div>
      </div>

      <!-- Per-band lanes: operators care whether THEIR band is clear, not
           how bands compare, so each band gets its own row. Each lane is a
           run of bottom-aligned slices: height AND colour are the interferer
           count scaled to that band's own peak (so a quiet band still shows
           its shape), on the green -> amber -> red ramp. Collapsed lanes are
           numberless; clicking one expands it with that band's tick values. -->
      <div v-if="days.length && bands.length" class="lanes-wrap">
        <!-- Pass numbers, centred over their boxes -->
        <div v-if="passMarks.length" class="pass-row">
          <div class="x-axis-spacer" />
          <div class="pass-track">
            <span
              v-for="m in passMarks"
              :key="'pass-' + m.c"
              class="pass-label"
              :style="{ left: cToPct(m.c) + '%' }"
            >
              {{ m.label }}
            </span>
          </div>
        </div>
        <div class="lanes-body" @mouseleave="hoverBand = null">
          <div class="lanes-labels">
            <div
              v-for="band in visibleBandList"
              :key="'label-' + band"
              class="lane-label"
              :class="{
                expanded: expandedBand === band,
                hovered: hoverBand === band,
              }"
              @mouseenter="hoverBand = band"
              @click="onLaneClick(band)"
            >
              <span class="lane-name">{{ band }}</span>
              <template v-if="expandedBand === band">
                <div
                  v-for="tick in expandedYTicks"
                  :key="'lane-tick-' + tick.value"
                  class="lane-tick"
                  :style="{ bottom: tick.pct / (1 + LANE_HEADROOM) + '%' }"
                >
                  {{ tick.value }}
                </div>
              </template>
            </div>
          </div>
          <div
            ref="plot"
            class="lanes-plots"
            @mousedown="onPlotMouseDown"
            @mousemove="onPlotHover"
            @mouseleave="onPlotLeave"
          >
            <!-- Hovered cell's backdrop. An earlier sibling of the lanes so it
                 paints beneath the bars; the matching cell's border is lit
                 via .pass-cell.active. -->
            <div
              v-if="hoverCell"
              class="cell-highlight"
              :style="hoverCell.style"
            />
            <div class="lanes-stack">
              <div
                v-for="band in visibleBandList"
                :key="'lane-' + band"
                class="lane-plot"
                :class="{
                  expanded: expandedBand === band,
                  hovered: hoverBand === band,
                }"
                @mouseenter="hoverBand = band"
                @click="onCellClick(band, $event)"
              >
                <div v-if="expandedBand === band" class="lane-title">
                  {{ band }} · ASI Risk
                </div>
                <svg
                  class="lane-svg"
                  :viewBox="`${viewStart} ${-CHART_H * LANE_HEADROOM} ${viewEnd - viewStart} ${CHART_H * (1 + LANE_HEADROOM)}`"
                  preserveAspectRatio="none"
                >
                  <!-- One path per ramp step, each a run of narrow rects
                     rising from the baseline with a gap between neighbours.
                     The viewBox does the horizontal scaling on zoom. -->
                  <g :opacity="hoverBand && hoverBand !== band ? 0.3 : 1">
                    <g
                      :opacity="
                        (hoverSlices && hoverBand === band) || dragBars
                          ? 0.35
                          : 1
                      "
                    >
                      <path
                        v-for="(d, step) in bandBars[band]"
                        :key="step"
                        :d="d"
                        :fill="RAMP_COLORS[step]"
                        stroke="none"
                      />
                    </g>
                    <!-- While drag-zooming, the slices inside the selection
                       are redrawn at full strength over the dimmed lane so
                       it is clear exactly what the zoom will keep. -->
                    <template v-if="dragBars">
                      <path
                        v-for="(d, step) in dragBars[band]"
                        :key="'drag-' + step"
                        :d="d"
                        :fill="RAMP_COLORS[step]"
                        stroke="none"
                      />
                    </template>
                    <!-- The hovered slice, redrawn at full strength over the
                       dimmed lane so it is unmistakable which bar the
                       tooltip describes. -->
                    <path
                      v-if="
                        hoverSlices && hoverBand === band && hoverSlices[band]
                      "
                      :d="hoverSlices[band].d"
                      :fill="hoverSlices[band].color"
                      stroke="rgba(255, 255, 255, 0.9)"
                      stroke-width="1"
                      vector-effect="non-scaling-stroke"
                    />
                  </g>
                </svg>
              </div>
            </div>
            <!-- One outlined cell per (pass, band), laid out to match the
                 lane rows exactly, so the chart reads as a grid with the
                 same clear gap between rows as between passes. -->
            <div
              v-for="seg in segments"
              :key="'box-' + seg.cstart"
              class="pass-box"
              :style="{
                left: cToPct(seg.cstart) + '%',
                width: (seg.clen / (viewEnd - viewStart)) * 100 + '%',
              }"
            >
              <div
                v-for="band in visibleBandList"
                :key="'cell-' + band"
                class="pass-cell"
                :class="{
                  expanded: expandedBand === band,
                  placeholder: emptyBands[band],
                  active:
                    !emptyBands[band] &&
                    hoverCell &&
                    hoverCell.band === band &&
                    hoverCell.cstart === seg.cstart,
                }"
              />
            </div>
            <!-- A band with nothing in the whole window gets one cell across
                 all the passes saying so, instead of a row of empty boxes. -->
            <div
              v-for="band in visibleBandList.filter((b) => emptyBands[b])"
              :key="'empty-' + band"
              class="empty-row"
              :style="rowGeometry[band]"
            >
              No data
            </div>
            <div
              v-if="hasLoadedData && !segments.length"
              class="no-passes-note"
            >
              No passes in this window
            </div>
            <div
              v-if="
                nowMarkerC !== null &&
                nowMarkerC > viewStart &&
                nowMarkerC < viewEnd
              "
              class="now-line"
              :style="{ left: cToPct(nowMarkerC) + '%' }"
            />
            <div
              v-if="dragSelectionStyle"
              class="drag-selection"
              :style="dragSelectionStyle"
            />
            <div
              v-if="hoverSlot && hasLoadedData"
              class="hover-line"
              :style="{ left: cToPct(hoverSlot.cx) + '%' }"
            />
            <div
              v-if="hoverInfo"
              class="hover-tooltip"
              :class="{ flip: hoverTooltipFlipped }"
              :style="{ left: cToPct(hoverSlot.cx) + '%' }"
            >
              <div class="hover-tooltip-time">{{ hoverInfo.label }}</div>
              <div v-if="!hoverInfo.covered" class="hover-tooltip-nocoverage">
                Not covered
              </div>
              <div
                v-for="row in hoverInfo.rows"
                :key="row.band"
                class="hover-tooltip-row"
                :class="{ 'hover-tooltip-row-active': row.band === hoverBand }"
              >
                <span class="tone-swatch" :style="{ background: row.color }" />
                <span class="hover-tooltip-band">{{ row.band }}</span>
                <span class="hover-tooltip-count">{{ row.count }}</span>
                <span class="hover-tooltip-tone">{{ row.toneLabel }}</span>
              </div>
              <div
                v-if="hoverInfo.rows.length === 0"
                class="hover-tooltip-empty"
              >
                No bands selected
              </div>
              <div
                v-if="hoverTelemetry !== null && telemetryVisible"
                class="hover-tooltip-row hover-tooltip-tlm"
              >
                <svg
                  class="chip-swatch"
                  width="14"
                  height="8"
                  viewBox="0 0 14 8"
                >
                  <line
                    x1="0"
                    y1="4"
                    x2="14"
                    y2="4"
                    :stroke="TLM_COLOR"
                    stroke-width="2"
                  />
                </svg>
                <span class="hover-tooltip-band">{{ tlmItem }}</span>
                <span class="hover-tooltip-count">{{ hoverTelemetry }}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="x-axis-row">
          <div class="x-axis-spacer" />
          <div class="x-axis">
            <span
              v-for="mark in axisMarks"
              :key="'mark-' + (mark.align || 'c') + mark.c"
              class="hour-mark"
              :class="'align-' + (mark.align || 'center')"
              :style="{ left: cToPct(mark.c) + '%' }"
            >
              {{ mark.label }}
            </span>
          </div>
        </div>
        <!-- Ramp legend: slice colour (and height) is the interferer count
             relative to that band's own peak across the loaded days. -->
        <div class="ramp-legend">
          <span>Low ASI Risk</span>
          <span class="ramp-swatch" :style="{ background: rampCss }" />
          <span>High ASI Risk</span>
          <button
            type="button"
            class="asi-info-btn"
            title="What ASI risk is and how it is calculated"
            @click="showAsiInfo = true"
          >
            <v-icon size="15">mdi-information-outline</v-icon>
            ASI Risk Overview
          </button>
        </div>

        <v-dialog v-model="showAsiInfo" max-width="600">
          <v-card class="asi-info">
            <v-card-title class="asi-info-title">ASI Risk Overview</v-card-title>
            <v-card-text class="asi-info-body">
              <p>
                <strong>Adjacent satellite interference (ASI)</strong> is
                the risk that another satellite transmitting in the same
                frequency band is in your ground station's view at the same
                time as the satellite you are tracking, so its signal can
                land in your receiver alongside the one you want.
              </p>
              <h4>How Vega calculates it</h4>
              <ol>
                <li>
                  <strong>Visibility.</strong> Vega propagates the orbit of
                  the selected satellite and works out, minute by minute,
                  when it is above the horizon from the selected ground
                  station. Those minutes are the passes you see as boxes;
                  a satellite that is always in view (GEO) gives one
                  box for the whole day.
                </li>
                <li>
                  <strong>Candidates.</strong> From the catalog of tracked
                  satellites it selects the ones whose transmit frequencies
                  overlap a band the selected satellite uses. Satellites in
                  other bands are ignored.
                </li>
                <li>
                  <strong>Overlap.</strong> For every covered minute and
                  every band, it counts how many of those candidates are
                  simultaneously in view of the station. That count is the
                  <strong>interferer count</strong> - the number behind each
                  bar.
                </li>
              </ol>
              <h4>Reading the chart</h4>
              <ul>
                <li>
                  Each bar is one minute (or a few minutes when the view is
                  too narrow to show them individually - the tooltip then
                  says which). Its height and colour are that minute's
                  interferer count relative to the band's busiest minute in
                  the loaded day, from green (quiet) through amber to red
                  (the peak). The tooltip gives the actual count.
                </li>
                <li>
                  Vega's own severity scale is absolute: a minute with
                  1 or more interferers is a <em>warning</em> and 10 or more
                  is <em>high</em>. The COSMOS limits on the
                  <code>FORECASTING_SUMMARY</code> packet use that scale.
                </li>
                <li>
                  Today and the next two days come from the latest forecast
                  run (refreshed several times a day); earlier days are the
                  measured record for that day. The chart only shows time
                  when the satellite is in view - gaps between passes are
                  removed.
                </li>
              </ul>
              <p class="asi-info-note">
                Counts are geometric and spectral - they say how many
                same-band satellites share the station's sky, not the
                received power of each. Treat a high count as a cue to
                check the pass, not as a measured carrier-to-interference
                ratio.
              </p>
            </v-card-text>
            <v-card-actions>
              <v-spacer />
              <v-btn variant="text" @click="showAsiInfo = false">Close</v-btn>
            </v-card-actions>
          </v-card>
        </v-dialog>
      </div>
    </template>
  </div>
</template>

<script>
import { Cable, OpenC3Api } from '@openc3/js-common/services'
// Deliberately no import of the COSMOS vue-common Widget mixin: it pulls
// ~2 MB of the COSMOS shell (which already loads it) into this bundle, and the
// only things this widget used from it were the props declared below and
// computedStyle.

// The chart shows a sliding WINDOW_DAYS-wide window; each chevron click
// slides it by one day. windowOffsetDays is the window's FIRST day relative
// to today: the default (0) shows today, the forward cap (+2) reaches the
// far edge of the 72h forecast, and back it can slide MAX_BACK_DAYS into
// the measured archive. Past days load from GET_HISTORY, today/forecast
// days from GET_DAY_DETAIL; each loaded day is cached (see loadForecast).
const WINDOW_DAYS = 1
const DEFAULT_WINDOW_OFFSET = 0
const MAX_FORWARD_OFFSET = 2
const MAX_BACK_DAYS = 30
// --- Pass-compressed x axis ---
// LEO passes are minutes long with hours of nothing between them; on a
// clock axis the chart is mostly empty zero-line. Instead the x axis shows
// ONLY the passes, laid end to end with a vertical separator between them,
// each labeled underneath with its time range and pass number. Chart x
// coordinates are "compressed units": 1 unit = 1 minute inside a pass;
// between passes sits a gap that is PASS_GAP_PX wide on screen whatever the
// zoom (passGapUnits converts it), so each pass reads as its own block. A
// satellite that is always visible (GEO) yields a single day-long pass and
// keeps normal clock ticks.
const PASS_GAP_PX = 8
// Vertical gap between band rows - the same size as the gap between
// passes, so the chart reads as a grid of (pass x band) cells.
const LANE_GAP_PX = 8
// Context minutes on each side of a pass. Zero: slices (unlike the old
// lines) don't need to rise from a baseline, and any padding is dead space
// inside the box.
const PASS_PAD_MIN = 0

// Today/forecast day responses go stale (the forecast refreshes, and
// today's measured portion keeps growing); past days never do.
const FORECAST_CACHE_TTL_MS = 5 * 60_000
const WEEKDAYS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']
const MONTHS = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
]
// SVG viewBox height for the plot (y grows downward: 0 = top = max value,
// CHART_H = bottom = 0 interactions). Width (viewBox x-range) is
// viewStart..viewEnd, in minutes - zooming just narrows this window, it
// never touches the underlying path data.
const CHART_H = 220
// Empty space kept above a lane's tallest slice, as a fraction of CHART_H,
// so a band at its peak never runs into the lane above it.
const LANE_HEADROOM = 0.14

// --- Time zone ---
// The chart follows the COSMOS 'time_zone' setting (Admin / Settings), the
// same one the top-bar clock uses: 'local' (the browser's zone), 'UTC', or
// an IANA zone name. Days are that zone's calendar days (midnight to
// midnight there), and every label is rendered in it. Vega's API is queried
// by UTC date, so a display day is stitched from the one or two UTC days
// that overlap it (see utcFetchDays).
const partsFormatters = {}
function zoneParts(ms, tz) {
  const key = tz || 'local'
  let fmt = partsFormatters[key]
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: key === 'local' ? undefined : key,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      weekday: 'short',
    })
    partsFormatters[key] = fmt
  }
  const p = {}
  for (const part of fmt.formatToParts(new Date(ms))) p[part.type] = part.value
  return {
    y: Number(p.year),
    m: Number(p.month) - 1,
    d: Number(p.day),
    hh: Number(p.hour) % 24,
    mm: Number(p.minute),
    wd: String(p.weekday).slice(0, 3).toUpperCase(),
  }
}
// Minutes the zone is ahead of UTC at the given instant.
function zoneOffsetMin(ms, tz) {
  const p = zoneParts(ms, tz)
  return (
    (Date.UTC(p.y, p.m, p.d, p.hh, p.mm) - Math.floor(ms / 60000) * 60000) /
    60000
  )
}
// Epoch ms of midnight on the zone's calendar day (y, m, d). Two passes so
// a DST change between the guess and the answer is absorbed.
function zoneMidnightMs(y, m, d, tz) {
  const guess = Date.UTC(y, m, d)
  const first = guess - zoneOffsetMin(guess, tz) * 60000
  return guess - zoneOffsetMin(first, tz) * 60000
}
function pad2(n) {
  return String(n).padStart(2, '0')
}
// Colour ramp. Each slice is coloured by its interferer count RELATIVE to
// the band's own peak in the loaded window - green (quiet) through amber to
// red (the band's worst minute) - the same continuous low -> high strip the
// Vega app draws. Relative, not the API's absolute tone thresholds: with
// real traffic every minute clears "high >= 10", which paints the whole day
// one colour and says nothing. The ramp is quantised to RAMP_STEPS colours
// so a lane is at most RAMP_STEPS <path> elements no matter how many
// minutes it holds. Level is also encoded by slice height and spelled out
// in the tooltip, so hue is never the only cue.
const RAMP_STEPS = 16
const RAMP_STOPS = [
  [0x43, 0xa0, 0x47], // green
  [0xff, 0xb3, 0x00], // amber
  [0xe5, 0x39, 0x35], // red
]
function rampColor(level) {
  const t = Math.min(1, Math.max(0, level)) * (RAMP_STOPS.length - 1)
  const i = Math.min(RAMP_STOPS.length - 2, Math.floor(t))
  const f = t - i
  const rgb = RAMP_STOPS[i].map((a, k) =>
    Math.round(a + (RAMP_STOPS[i + 1][k] - a) * f),
  )
  return `rgb(${rgb.join(',')})`
}
const RAMP_COLORS = Array.from({ length: RAMP_STEPS }, (_, i) =>
  rampColor(i / (RAMP_STEPS - 1)),
)
// Fraction of each slot a slice fills; the rest is the gap that makes
// neighbouring slices read as separate bars rather than a filled area.
const SLICE_FILL = 0.7
// Minimum on-screen width of one slot (slice + gap), in CSS px. When a
// lane can't give every minute that much room, minutes are grouped into
// slots of 2, 3, ... minutes (worst minute wins) so the slices stay visible.
const MIN_SLOT_PX = 4

// Header options for every cmd() this widget sends. The js-common axios
// layer pops a global "Network error" toast for any failed API call and
// prints the request body in it - which for our commands includes the
// user's API key. Listing the statuses here tells it to skip the toast and
// just reject, so the widget reports failures in its own words (and
// retries the transient ones) with the key never on screen.
const CMD_OPTS = {
  headers: { 'Ignore-Errors': '400 401 403 404 408 422 500 502 503 504' },
}

// CVT poll cadence while waiting for a command's HTTP response to land, and
// how long "check again" waits for APPROVED_ORGS to refresh before it
// classifies whatever is there.
const POLL_INTERVAL_MS = 400
const INTEGRATION_CHECK_TIMEOUT_MS = 8000
// Every VEGA command names ERROR_RESPONSE as its HTTP_ERROR_PACKET, and
// COSMOS routes any HTTP status >= 300 there INSTEAD of the command's own
// packet - so a success packet never carries an error status, and an error
// is only visible by watching ERROR_RESPONSE. It is shared by all commands
// (background periodic polls included), so it is attributed to a request
// only when it landed after that request's stamp-before-send.
const ERROR_PACKET = 'ERROR_RESPONSE'
const ERROR_ITEMS = ['RECEIVED_TIMESECONDS', 'HTTP_STATUS', 'BODY']
// Everything the connection check reads, in one get_tlm_values call.
const INTEGRATION_SPEC = {
  APPROVED_ORGS: ['RECEIVED_TIMESECONDS', 'HTTP_STATUS', 'ORGANIZATIONS_JSON'],
  [ERROR_PACKET]: ERROR_ITEMS,
}
// RECEIVED_TIMESECONDS of a packet snapshot ({ ITEM: value }), 0 if never
// received.
function stampOf(values) {
  return Number(values?.RECEIVED_TIMESECONDS) || 0
}
// The interesting part of an ERROR_RESPONSE body for a user-facing message:
// a short plain string, never an HTML page or a JSON blob.
function shortErrorBody(body) {
  if (typeof body !== 'string') return ''
  const text = body.trim()
  if (!text || text.length >= 200 || text.startsWith('<')) return ''
  return text
}
const VEGA_API_KEYS_URL = 'https://app.vega.space/settings/api-keys'
const VEGA_SIGNUP_URL = 'https://app.vega.space/signup'
const VEGA_APP_URL = 'https://app.vega.space'
// The user's own Vega API key is kept in this browser only. It is never
// written to a COSMOS setting (get_setting needs no more than viewer rights,
// so that would expose it to every user) - see authOverride().
const API_KEY_LS_KEY = 'vega_widget_api_key'
function readStoredApiKey() {
  try {
    return localStorage.getItem(API_KEY_LS_KEY) || null
  } catch (e) {
    return null // storage blocked (private mode etc.) - key lasts this page only
  }
}
// Org workspace pages use /organizations/external/{slug}-{id}/configuration/...
// - the slug is cosmetic (the route also accepts a bare numeric id with no
// slug prefix), so we skip generating one and just use the id.
function vegaWorkspaceUrl(orgId, subpath) {
  if (!orgId) return VEGA_APP_URL
  return `${VEGA_APP_URL}/organizations/external/${orgId}/configuration/${subpath}`
}
// The heatmap isn't its own page - it lives inside the forecast detail view,
// which needs a satellite id. With one selected we deep-link straight to that
// satellite's heatmap; without one we fall back to the forecast list. The
// date segment is optional and Vega auto-selects the first available day, so
// we omit it rather than risk pointing at a day with no forecast.
function vegaForecastUrl(orgId, satelliteId) {
  if (!orgId) return VEGA_APP_URL
  const base = `${VEGA_APP_URL}/organizations/external/${orgId}/forecast`
  return satelliteId ? `${base}/${satelliteId}` : base
}
// Candidate tick spacings (minutes) for the x axis - picks whichever gives
// ~4-8 labels for the current visible span.
const TICK_INTERVALS = [1, 2, 5, 10, 15, 30, 60, 120, 180, 360, 720, 1440]

// --- Satellite telemetry overlay (real COSMOS telemetry, not Vega data) ---
// The user picks any target/packet/item; its decommutated history from the
// start of the chart window (today 00:00 UTC) through "now" streams in over
// the same StreamingChannel websocket TlmGrapher uses, and renders as one
// extra line on its own right-hand axis. White so it can't be confused with
// a Vega band color.
const TLM_COLOR = '#ffffff'
// Feature flag: the COSMOS telemetry overlay is parked for now (2026-09-08,
// user request) while the focus is Vega historical data. Flip to true to
// bring the whole overlay (picker row, line, right axis, tooltip row) back.
const TLM_OVERLAY_ENABLED = false
// localStorage key remembering the selected overlay item across reloads
const TLM_OVERLAY_LS_KEY = 'vega_widget_tlm_overlay'
// Reduced-minute data keeps the 72h window to <=4320 points. If the reducer
// hasn't produced data for this item yet (new install, non-numeric item),
// fall back to raw DECOM after this many ms of silence.
const TLM_REDUCED_FALLBACK_MS = 12000
// Telemetry samples are bucketed to whole minutes (matching the forecast
// resolution); a gap larger than this many minutes breaks the line rather
// than drawing a false straight segment across missing data.
const TLM_GAP_MINUTES = 5
// Internal packet bookkeeping items - noise in the item picker
const TLM_ITEM_BLOCKLIST = new Set([
  'PACKET_TIMESECONDS',
  'PACKET_TIMEFORMATTED',
  'RECEIVED_TIMESECONDS',
  'RECEIVED_TIMEFORMATTED',
])

export default {
  // The COSMOS screen passes a handful of extra props (widgetIndex,
  // namedWidgets, line, ...) meant for the stock Widget mixin; keep the ones
  // we don't declare from landing on the root element as attributes.
  inheritAttrs: false,
  props: {
    // TARGET/PACKET etc. from the screen definition line (unused here - the
    // widget always talks to the VEGA target)
    parameters: {
      type: Array,
      default: () => [],
    },
    // SETTING lines following the widget, e.g. ['WIDTH', '900']
    settings: {
      type: Array,
      default: () => [],
    },
    // Values the screen polls for us, keyed TGT__PKT__ITEM__TYPE. Unused: this
    // widget reads the CVT on demand after each command it sends.
    screenValues: {
      type: Object,
      default: () => ({}),
    },
  },
  emits: ['addItem', 'deleteItem'],
  data() {
    return {
      CHART_H,
      LANE_HEADROOM,
      RAMP_COLORS,
      // COSMOS 'time_zone' setting - see the Time zone block up top.
      timeZone: 'local',
      // Wall clock, ticked every 30s so the "now" line moves.
      nowMs: Date.now(),
      showAsiInfo: false,
      // CSS px width of the lanes area, kept current by a ResizeObserver;
      // drives how many minutes each slice covers (see slotMinutes).
      laneWidthPx: 0,
      VEGA_API_KEYS_URL,
      VEGA_SIGNUP_URL,
      // true once we've classified the last APPROVED_ORGS response as not a
      // working connection - shows the setup/onboarding state instead of the
      // normal pickers/chart.
      notIntegrated: false,
      // 'checking' | 'connected' | 'missing_key' | 'no_access' | 'unavailable'
      integrationState: 'checking',
      // Browser-held Vega API key (see API_KEY_LS_KEY) and the entry form
      apiKeyInput: '',
      savedApiKey: readStoredApiKey(),
      savingKey: false,
      saveKeyError: '',
      checkingIntegration: false,
      // Error from the last "check again" attempt (e.g. the command could not
      // be sent because VEGA_INT is not connected).
      integrationCheckError: '',
      // HTTP status (and short body) of the ERROR_RESPONSE that produced the
      // current non-connected state, for the message; null when unknown.
      integrationStatus: null,
      integrationDetail: '',
      organizations: [],
      selectedOrgId: null,
      workspaceLoading: false,
      workspaceRequestId: 0,
      satellites: [],
      groundStations: [],
      // null = unknown yet (e.g. still loading, or the lookup failed) - the
      // satellite picker stays unsorted/fully-enabled in that case rather
      // than assuming no satellite has a forecast. Once populated it's
      // { [satelliteId]: true/false }.
      forecastAvailableBySatId: null,
      selectedSatelliteId: null,
      selectedGroundStationId: null,
      // dayDataByDate[date] = { minutes: [...], toneWarningMin, toneHighMin }
      dayDataByDate: {},
      // First day of the sliding window, relative to today (see the
      // WINDOW_DAYS constants above).
      windowOffsetDays: DEFAULT_WINDOW_OFFSET,
      MAX_BACK_DAYS,
      MAX_FORWARD_OFFSET,
      DEFAULT_WINDOW_OFFSET,
      // visibleBands[band] = true/false - which lines are toggled on
      visibleBands: {},
      loading: false,
      progressText: '',
      errorText: '',
      // null = fully zoomed out (0..totalMinutes). Otherwise [start, end] in
      // absolute minute-index units, set by click-drag on the chart.
      zoomRange: null,
      dragStartPx: null,
      dragCurrentPx: null,
      // Absolute minute-index the mouse is currently hovering, or null when
      // not hovering / mid-drag-zoom.
      hoverIdx: null,
      // Band whose lane is click-expanded (larger, with y-tick values),
      // or null when all lanes are collapsed sparklines.
      expandedBand: null,
      // Band whose lane the mouse is currently over - its line/label are
      // highlighted and the other lanes dimmed.
      hoverBand: null,
      // --- Satellite telemetry overlay state ---
      TLM_COLOR,
      TLM_OVERLAY_ENABLED,
      tlmTargets: [],
      tlmPackets: [],
      tlmItems: [],
      tlmTarget: null,
      tlmPacket: null,
      tlmItem: null,
      telemetryVisible: true,
      tlmError: '',
      // Incremented per received batch; the point/path computeds depend on it
      // so the (non-reactive) bucket map below doesn't need deep reactivity.
      tlmVersion: 0,
    }
  },
  computed: {
    orgOptions() {
      return this.organizations.map((o) => ({
        id: o.id,
        label:
          o.name +
          (o.satellites_count != null ? ` (${o.satellites_count} sat)` : ''),
      }))
    },
    savedApiKeyTail() {
      return this.savedApiKey ? this.savedApiKey.slice(-4) : ''
    },
    integrationTitle() {
      switch (this.integrationState) {
        case 'no_access':
          return 'No approved organizations yet'
        case 'missing_key':
          return this.savedApiKey
            ? 'Vega rejected the saved API key'
            : 'Enter your Vega API key'
        case 'checking':
          return 'Checking the Vega connection…'
        default:
          return this.integrationStatus
            ? `Vega returned HTTP ${this.integrationStatus}`
            : 'Vega is not responding'
      }
    },
    integrationMessage() {
      const detail = this.integrationDetail
        ? ` (${this.integrationDetail})`
        : ''
      switch (this.integrationState) {
        case 'no_access':
          return `The API key works, but its user has no approved organization access${detail}. Approve an organization in Vega, then check again.`
        case 'missing_key':
          return this.savedApiKey
            ? `Vega rejected the saved API key (HTTP 401${detail}). Enter a new one below.`
            : 'Vega needs your API key to load forecasts. Paste it below - it stays in this browser.'
        case 'checking':
          return 'Reading the last Vega response from COSMOS…'
        default:
          return `${
            this.integrationStatus
              ? `Vega returned HTTP ${this.integrationStatus}${detail}.`
              : 'COSMOS has no response from VEGA_INT yet.'
          } Check that the VEGA_INT interface is connected, then check again${
            this.savedApiKey
              ? ''
              : ' - and if you have not entered your Vega API key yet, add it below'
          }.`
      }
    },
    // The setup steps only help when the setup is what's missing - in
    // 'no_access' the key already works, the org approval is the blocker.
    showSetupSteps() {
      return ['missing_key', 'unavailable'].includes(this.integrationState)
    },
    // Style from the screen's SETTING lines (WIDTH/HEIGHT/RAW), the subset of
    // the COSMOS Widget mixin's computedStyle this widget needs.
    computedStyle() {
      const style = {}
      for (const setting of this.settings) {
        const [key, value, extra] = setting
        if (key === 'WIDTH' || key === 'HEIGHT') {
          style[key.toLowerCase()] = Number.isFinite(Number(value))
            ? `${value}px`
            : value
        } else if (typeof key === 'string' && key.startsWith('RAW') && value) {
          style[value.toLowerCase()] = extra
        }
      }
      return style
    },
    selectedOrg() {
      return this.organizations.find((o) => o.id === this.selectedOrgId) || null
    },
    vegaSatellitesUrl() {
      return vegaWorkspaceUrl(this.selectedOrgId, 'satellites')
    },
    vegaGroundStationsUrl() {
      return vegaWorkspaceUrl(this.selectedOrgId, 'ground-stations')
    },
    vegaHeatmapUrl() {
      return vegaForecastUrl(this.selectedOrgId, this.selectedSatelliteId)
    },
    // Satellites with an available forecast sort to the top; the rest are
    // still listed (so it's clear they exist) but disabled, since a
    // GET_DAY_DETAIL call against them would just come back empty. When
    // availability isn't known yet (still loading / lookup failed), nothing
    // is disabled or reordered rather than assuming the worst.
    satelliteOptions() {
      const known = this.forecastAvailableBySatId
      const options = this.satellites.map((s) => {
        const available = known ? !!known[s.id] : true
        return {
          id: s.id,
          label:
            s.name +
            (s.norad ? ` (NORAD ${s.norad})` : '') +
            (known && !available ? ' — no forecast' : ''),
          disabled: known ? !available : false,
        }
      })
      if (!known) return options
      return options.sort((a, b) => Number(a.disabled) - Number(b.disabled))
    },
    groundStationOptions() {
      return this.groundStations.map((gs) => ({ id: gs.id, label: gs.name }))
    },
    selectedSatellite() {
      return (
        this.satellites.find((s) => s.id === this.selectedSatelliteId) || null
      )
    },
    selectedGroundStation() {
      return (
        this.groundStations.find(
          (gs) => gs.id === this.selectedGroundStationId,
        ) || null
      )
    },
    bands() {
      return (this.selectedSatellite && this.selectedSatellite.bands) || []
    },
    // Bands currently shown as lanes (the legend chips toggle these).
    visibleBandList() {
      return this.bands.filter((b) => this.visibleBands[b])
    },
    // The WINDOW_DAYS-day sliding window, first day at windowOffsetDays
    // relative to today. `past` days are filled by GET_HISTORY (measured,
    // per-band); today and forecast days by GET_DAY_DETAIL.
    days() {
      const result = []
      for (let i = 0; i < WINDOW_DAYS; i++) {
        result.push(this.dayInfo(this.windowOffsetDays + i))
      }
      return result
    },
    // The calendar menu's rows: the last four days through the next three,
    // oldest first. Days beyond the forecast horizon are listed but
    // disabled, so the horizon is visible rather than a surprise.
    calendarDays() {
      const rows = []
      for (let o = -4; o <= 3; o++) {
        const d = this.dayInfo(o)
        const disabled = o > MAX_FORWARD_OFFSET || o < -MAX_BACK_DAYS
        const kind = o < 0 ? 'past' : o === 0 ? 'today' : 'forecast'
        rows.push({
          ...d,
          offset: o,
          kind,
          disabled,
          kindLabel: disabled ? 'no forecast yet' : kind,
        })
      }
      return rows
    },
    // The Yesterday / Today / Tomorrow toggle: reflects the window when it
    // is on one of those days, nothing selected otherwise.
    quickDay: {
      get() {
        const o = this.windowOffsetDays
        return o >= -1 && o <= 1 ? o : null
      },
      set(v) {
        if (v === null || v === undefined) return
        this.setWindowOffset(v)
      },
    },
    // The UTC calendar days Vega must be asked for to cover the display
    // window - one, or two when the zone's midnight isn't UTC's. 'past'
    // (measured history vs. forecast) is decided per UTC day, since that is
    // how the API splits them.
    utcFetchDays() {
      const start = this.day0StartMs
      const end = start + this.totalMinutes * 60000
      const todayUtc = new Date().toISOString().slice(0, 10)
      const s = new Date(start)
      let t = Date.UTC(s.getUTCFullYear(), s.getUTCMonth(), s.getUTCDate())
      const result = []
      while (t < end) {
        const date = new Date(t).toISOString().slice(0, 10)
        result.push({ date, past: date < todayUtc })
        t += 86400000
      }
      return result
    },
    // Minute-index of "now" - the divider between measured and predicted.
    // Recomputed on render passes, not a live clock; close enough for a
    // marker on a multi-day chart.
    nowIdx() {
      return (this.nowMs - this.day0StartMs) / 60000
    },
    totalMinutes() {
      return this.days.length * 1440
    },
    day0StartMs() {
      return this.days[0].startMs
    },
    // Lookup: absolute minute index -> that minute's data entry (or null).
    minuteEntries() {
      const map = new Array(this.totalMinutes).fill(null)
      const start = this.day0StartMs
      for (const dayData of Object.values(this.dayDataByDate)) {
        for (const entry of dayData.minutes || []) {
          const idx = Math.round(
            (new Date(entry.timestamp).getTime() - start) / 60000,
          )
          if (idx >= 0 && idx < map.length) map[idx] = entry
        }
      }
      return map
    },
    // Contiguous covered spans (passes), padded by PASS_PAD_MIN each side
    // and merged when the padding makes them touch.
    passes() {
      const entries = this.minuteEntries
      const spans = []
      let start = null
      for (let i = 0; i <= entries.length; i++) {
        const covered =
          i < entries.length && !!(entries[i] && entries[i].covered)
        if (covered && start === null) start = i
        if (!covered && start !== null) {
          spans.push([start, i])
          start = null
        }
      }
      const merged = []
      for (const [s, e] of spans) {
        const ps = Math.max(0, s - PASS_PAD_MIN)
        const pe = Math.min(entries.length, e + PASS_PAD_MIN)
        const last = merged[merged.length - 1]
        if (last && ps <= last[1]) last[1] = Math.max(last[1], pe)
        else merged.push([ps, pe])
      }
      return merged.map(([s, e]) => ({
        startIdx: s,
        endIdx: e,
        startLabel: this.formatHM(this.idxToDate(s + PASS_PAD_MIN)),
        endLabel: this.formatHM(this.idxToDate(e - PASS_PAD_MIN)),
      }))
    },
    // The between-pass gap in compressed units: PASS_GAP_PX of the fully
    // zoomed-out lane width, solved so the passes plus the gaps fill it.
    passGapUnits() {
      const n = this.passes.length
      if (n < 2) return 0
      const minutes = this.passes.reduce(
        (sum, p) => sum + (p.endIdx - p.startIdx),
        0,
      )
      const px = this.laneWidthPx || 1200
      return (PASS_GAP_PX * minutes) / Math.max(1, px - PASS_GAP_PX * (n - 1))
    },
    // Passes laid out in compressed x coordinates, passGapUnits apart.
    segments() {
      let c = 0
      const gap = this.passGapUnits
      return this.passes.map((p, i) => {
        const seg = {
          ...p,
          index: i + 1,
          cstart: c,
          clen: p.endIdx - p.startIdx,
        }
        c += seg.clen + gap
        return seg
      })
    },
    totalCompressed() {
      const segs = this.segments
      if (!segs.length) return 1
      const last = segs[segs.length - 1]
      return last.cstart + last.clen
    },
    viewStart() {
      return this.zoomRange ? this.zoomRange[0] : 0
    },
    viewEnd() {
      return this.zoomRange ? this.zoomRange[1] : this.totalCompressed
    },
    zoomSpanLabel() {
      const span = this.viewEnd - this.viewStart
      if (span < 120) return `${Math.round(span)}m`
      if (span < 1440) return `${(span / 60).toFixed(1)}h`
      return `${(span / 1440).toFixed(1)}d`
    },
    // "now" marker in compressed coordinates: inside a pass it lands exactly
    // there; between passes it sits on the separator; null once past the
    // last pass (or before data loads).
    nowMarkerC() {
      const idx = this.nowIdx
      const c = this.idxToC(Math.floor(idx))
      if (c !== null) return c + (idx - Math.floor(idx))
      for (const seg of this.segments) {
        if (idx < seg.startIdx) return seg.cstart - this.passGapUnits / 2
      }
      return null
    },
    // X-axis labels in compressed coordinates. A single day-long pass (GEO,
    // always visible) keeps normal clock ticks; otherwise each pass is
    // labeled once, centered under its segment, with its time range.
    axisMarks() {
      const segs = this.segments
      if (!segs.length) return []
      if (segs.length === 1 && segs[0].clen >= 720) {
        const seg = segs[0]
        const span = this.viewEnd - this.viewStart
        const rough = span / 7
        let interval = TICK_INTERVALS[TICK_INTERVALS.length - 1]
        for (const opt of TICK_INTERVALS) {
          if (rough <= opt) {
            interval = opt
            break
          }
        }
        // Only the ticks inside the (possibly zoomed) window, with the two
        // edges always labelled: the first tick flush left, the last flush
        // right. A tick within a quarter-interval of an edge is dropped so
        // it can't collide with the edge label.
        const vStart = this.viewStart
        const vEnd = this.viewEnd
        const toIdx = (c) => seg.startIdx + (c - seg.cstart)
        const labelAt = (idx) => {
          const hm = this.formatHM(this.idxToDate(idx))
          return idx === seg.endIdx && hm === '00:00' ? '24:00' : hm
        }
        const marks = [
          { c: vStart, label: labelAt(toIdx(vStart)), align: 'start' },
        ]
        const first = Math.ceil(toIdx(vStart) / interval) * interval
        for (let idx = first; idx < toIdx(vEnd); idx += interval) {
          const c = seg.cstart + (idx - seg.startIdx)
          if (c - vStart < interval / 4 || vEnd - c < interval / 4) continue
          marks.push({ c, label: labelAt(idx) })
        }
        marks.push({ c: vEnd, label: labelAt(toIdx(vEnd)), align: 'end' })
        return marks
      }
      // Each pass is its own little chart: start time on its left edge, end
      // time on its right, pass number centred beneath. A box too narrow
      // for two times keeps only its start time.
      const pxPerUnit =
        (this.laneWidthPx || 1200) / Math.max(1, this.viewEnd - this.viewStart)
      return segs.flatMap((s) => {
        const marks = [{ c: s.cstart, label: s.startLabel, align: 'start' }]
        if (s.clen * pxPerUnit >= 72) {
          marks.push({ c: s.cstart + s.clen, label: s.endLabel, align: 'end' })
        }
        return marks
      })
    },
    // Each lane is scaled to ITS OWN band's peak, not a shared maximum -
    // severity is relative to the band (5 interferers on VHF can matter more
    // than 55 on S), and a shared scale would flatten quiet bands into
    // near-identical baselines. The expanded lane's tick values come from
    // the same per-band max, so the numbers stay honest.
    bandMaxes() {
      const result = {}
      for (const band of this.bands) {
        let max = 0
        for (const entry of this.minuteEntries) {
          if (!entry || !entry.covered) continue
          const c = (entry.counts && entry.counts[band]) || 0
          if (c > max) max = c
        }
        result[band] = this.niceMax(max)
      }
      return result
    },
    // Y-tick values for the click-expanded lane, on that band's own scale.
    expandedYTicks() {
      if (!this.expandedBand) return []
      const max = this.bandMaxes[this.expandedBand] || 1
      const steps = 4
      const ticks = []
      for (let i = 0; i <= steps; i++) {
        ticks.push({
          value: Math.round((max * i) / steps),
          pct: (i / steps) * 100,
        })
      }
      return ticks
    },
    // Minutes per slice slot: 1 whenever the lane is wide enough to give
    // every minute MIN_SLOT_PX, otherwise the smallest grouping that is.
    // Depends on the zoom window, so zooming in refines the slices back
    // toward one per minute.
    slotMinutes() {
      const px = this.laneWidthPx || 1200
      const span = Math.max(1, this.viewEnd - this.viewStart)
      return Math.max(1, Math.ceil((span * MIN_SLOT_PX) / px))
    },
    // One SVG path per band per ramp step. Recomputed when the data,
    // selection or slot size changes; the SVG viewBox still does the
    // horizontal scaling, so drag-zoom stays cheap.
    bandBars() {
      const result = {}
      for (const band of this.bands) {
        result[band] = this.buildBandBars(band)
      }
      return result
    },
    rampCss() {
      return `linear-gradient(90deg, ${RAMP_COLORS.join(', ')})`
    },
    // The drag-zoom selection in compressed units, or null when not
    // dragging (or the drag is still narrower than a click).
    dragRangeC() {
      if (this.dragStartPx === null || !this.laneWidthPx) return null
      const a = Math.min(this.dragStartPx, this.dragCurrentPx)
      const b = Math.max(this.dragStartPx, this.dragCurrentPx)
      if (b - a < 4) return null
      const span = this.viewEnd - this.viewStart
      return [
        this.viewStart + (a / this.laneWidthPx) * span,
        this.viewStart + (b / this.laneWidthPx) * span,
      ]
    },
    // Per band, the slices inside the drag selection - the same paths as
    // bandBars restricted to that range, drawn on top at full strength.
    dragBars() {
      const range = this.dragRangeC
      if (!range) return null
      const result = {}
      for (const band of this.bands) {
        result[band] = this.buildBandBars(band, range)
      }
      return result
    },
    // The slice slot under the cursor: its minute range [start, stop) and
    // the compressed x of its centre (for the crosshair and tooltip).
    hoverSlot() {
      const idx = this.hoverIdx
      if (idx === null) return null
      const seg = this.segments.find((s) => idx >= s.startIdx && idx < s.endIdx)
      if (!seg) return null
      const slot = this.slotMinutes
      const start =
        seg.startIdx + Math.floor((idx - seg.startIdx) / slot) * slot
      const stop = Math.min(seg.endIdx, start + slot)
      const c0 = seg.cstart + (start - seg.startIdx)
      return { seg, start, stop, cx: c0 + (stop - start) / 2 }
    },
    // Where each band's row sits, in px from the top of the plot - mirrors
    // the lane stack (46px rows, 220px expanded, LANE_GAP_PX between).
    rowGeometry() {
      const result = {}
      let top = 0
      for (const b of this.visibleBandList) {
        const h = this.expandedBand === b ? 220 : 46
        result[b] = { top: `${top}px`, height: `${h}px` }
        top += h + LANE_GAP_PX
      }
      return result
    },
    // Bands with no interference anywhere in the loaded window.
    emptyBands() {
      const result = {}
      if (!this.hasLoadedData) return result
      for (const band of this.bands) {
        let any = false
        for (const entry of this.minuteEntries) {
          if (entry && entry.covered && (entry.counts?.[band] || 0) > 0) {
            any = true
            break
          }
        }
        result[band] = !any
      }
      return result
    },
    // The hovered grid cell (pass x band): which one, and where its backdrop
    // goes.
    hoverCell() {
      const slot = this.hoverSlot
      const band = this.hoverBand
      if (!slot || !band || !this.visibleBands[band]) return null
      if (this.emptyBands[band]) return null
      const row = this.rowGeometry[band]
      if (!row) return null
      const span = this.viewEnd - this.viewStart
      return {
        band,
        cstart: slot.seg.cstart,
        style: {
          left: `${this.cToPct(slot.seg.cstart)}%`,
          width: `${(slot.seg.clen / span) * 100}%`,
          top: row.top,
          height: row.height,
        },
      }
    },
    // The hovered slice per band, ready to redraw on top of the dimmed lane.
    hoverSlices() {
      const slot = this.hoverSlot
      if (!slot) return null
      const result = {}
      for (const band of this.bands) {
        const g = this.sliceGeom(band, slot.seg, slot.start, slot.stop)
        if (g) result[band] = { d: g.d, color: rampColor(g.level) }
      }
      return result
    },
    // 'Pass N' over each pass box; none for a single day-long (GEO) pass.
    passMarks() {
      const segs = this.segments
      if (segs.length < 2) return []
      return segs.map((s) => ({
        c: s.cstart + s.clen / 2,
        label: `Pass ${s.index}`,
      }))
    },
    dragSelectionStyle() {
      if (this.dragStartPx === null) return null
      const left = Math.min(this.dragStartPx, this.dragCurrentPx)
      const width = Math.abs(this.dragCurrentPx - this.dragStartPx)
      return { left: `${left}px`, width: `${width}px` }
    },
    hasLoadedData() {
      return Object.keys(this.dayDataByDate).length > 0
    },
    // Flip the tooltip to the left of the cursor once it's past the
    // midpoint of the current view, so it doesn't run off the right edge.
    hoverTooltipFlipped() {
      return !!this.hoverSlot && this.cToPct(this.hoverSlot.cx) > 55
    },
    // The per-band interaction counts at the hovered minute, for the
    // currently-visible bands. null if not hovering, no data loaded yet, or
    // the hovered minute falls in a day that hasn't loaded.
    hoverInfo() {
      const slot = this.hoverSlot
      if (!slot) return null
      const dayIdx = Math.floor(this.hoverIdx / 1440)
      const day = this.days[dayIdx]
      if (!day) return null
      const entry = this.minuteEntries[this.hoverIdx]
      if (!entry) return null
      // With per-band lanes, the tooltip shows only the hovered lane's band
      // (falling back to all visible bands when no lane is under the cursor).
      // Counts are the slot's worst minute - the same number the bar shows.
      const rows = this.bands
        .filter((b) => this.visibleBands[b])
        .filter((b) => !this.hoverBand || b === this.hoverBand)
        .map((b) => {
          const count = this.slotCount(b, slot.start, slot.stop)
          const level = this.levelOf(count, b)
          return {
            band: b,
            count,
            color: count > 0 ? rampColor(level) : 'transparent',
            toneLabel:
              count > 0
                ? `${Math.round(level * 100)}% of ${b} peak`
                : entry.covered
                  ? 'Clear'
                  : '',
          }
        })
      const from = this.formatHM(this.idxToDate(slot.start))
      const to =
        slot.stop - slot.start > 1
          ? `–${this.formatHM(this.idxToDate(slot.stop - 1))}`
          : ''
      return {
        label: `${day.weekday} ${day.display} ${from}${to}`,
        covered: entry.covered,
        rows,
      }
    },
    // Sorted [minuteIdx, value] samples from the (non-reactive) bucket map.
    // tlmVersion is the reactivity hook - it bumps once per received batch.
    telemetryPoints() {
      this.tlmVersion // reactivity dependency
      const buckets = this._tlmBuckets || {}
      return Object.keys(buckets)
        .map(Number)
        .sort((a, b) => a - b)
        .map((k) => buckets[k])
    },
    // Value range for the overlay's own y scale, padded 5% so the line
    // doesn't hug the chart edges. A flat line gets an artificial +/-1 span.
    telemetryRange() {
      const pts = this.telemetryPoints
      if (!pts.length) return null
      let min = Infinity
      let max = -Infinity
      for (const [, v] of pts) {
        if (v < min) min = v
        if (v > max) max = v
      }
      if (min === max) {
        min -= 1
        max += 1
      }
      const pad = (max - min) * 0.05
      return { min: min - pad, max: max + pad }
    },
    telemetryPath() {
      const pts = this.telemetryPoints
      const range = this.telemetryRange
      if (!pts.length || !range) return ''
      const span = range.max - range.min
      let d = ''
      let lastIdx = null
      for (const [idx, v] of pts) {
        const y = CHART_H - ((v - range.min) / span) * CHART_H
        const cmd =
          lastIdx === null || idx - lastIdx > TLM_GAP_MINUTES ? 'M' : 'L'
        d += `${cmd}${idx.toFixed(1)},${y.toFixed(1)} `
        lastIdx = idx
      }
      return d.trim()
    },
    telemetryAxisVisible() {
      return !!this.tlmItem && this.telemetryPoints.length > 0
    },
    telemetryYTicks() {
      const range = this.telemetryRange
      if (!range) return []
      const steps = 4
      const ticks = []
      for (let i = 0; i <= steps; i++) {
        const value = range.min + ((range.max - range.min) * i) / steps
        ticks.push({
          label: this.formatTlmValue(value),
          pct: (i / steps) * 100,
        })
      }
      return ticks
    },
    // Overlay value at the hovered minute (nearest sample within 2 buckets),
    // or null - shown as an extra row in the hover tooltip.
    hoverTelemetry() {
      if (this.hoverIdx === null || !this.tlmItem) return null
      const buckets = this._tlmBuckets || {}
      this.tlmVersion // reactivity dependency
      for (const offset of [0, -1, 1, -2, 2]) {
        const hit = buckets[this.hoverIdx + offset]
        if (hit) return this.formatTlmValue(hit[1])
      }
      return null
    },
  },
  watch: {
    bands(newBands) {
      const v = {}
      newBands.forEach((b) => {
        v[b] = true
      })
      this.visibleBands = v
    },
    async selectedOrgId(newOrgId, oldOrgId) {
      if (!newOrgId || newOrgId === oldOrgId) return
      await this.loadWorkspaceForCurrentOrg(newOrgId)
    },
    // Auto-load: the chart fills in as soon as both pickers have a value -
    // on first open (the workspace load sets the defaults, which fires
    // these) and on any later dropdown change. loadForecast's generation
    // counter makes overlapping loads safe (the stale one is discarded).
    selectedSatelliteId(id, old) {
      if (!id || id === old) return
      if (this.selectedGroundStationId) this.loadForecast()
    },
    selectedGroundStationId(id, old) {
      if (!id || id === old) return
      if (this.selectedSatelliteId) this.loadForecast()
    },
    async tlmTarget(target) {
      if (this._restoringTlm) return
      this.tlmPacket = null
      this.tlmItem = null
      this.tlmPackets = []
      if (target) await this.loadTlmPackets(target)
    },
    async tlmPacket(packet) {
      if (this._restoringTlm) return
      this.tlmItem = null
      this.tlmItems = []
      if (packet) await this.loadTlmItems(this.tlmTarget, packet)
    },
    tlmItem(item) {
      if (this._restoringTlm) return
      try {
        if (item) {
          localStorage.setItem(
            TLM_OVERLAY_LS_KEY,
            JSON.stringify({
              target: this.tlmTarget,
              packet: this.tlmPacket,
              item,
            }),
          )
        } else {
          localStorage.removeItem(TLM_OVERLAY_LS_KEY)
        }
      } catch {
        // localStorage unavailable - selection just won't persist
      }
      this.restartTelemetryStream()
    },
  },
  async created() {
    this.api = new OpenC3Api()
    // Non-reactive telemetry-overlay internals (bucket map + websocket)
    this._tlmBuckets = {}
    this._tlmCable = null
    this._tlmSubscription = null
    this._tlmSubscribing = false
    this._tlmConnected = false
    this._tlmActiveKeys = []
    this._tlmFallbackTimer = null
    this._tlmStreamGen = 0
    this._forecastGen = 0
    // Per-(satellite, station, day) response cache - see loadForecast.
    this._dayCache = {}
    this._clockTimer = setInterval(() => {
      this.nowMs = Date.now()
    }, 30000)
    // Same setting the top-bar clock reads, so the chart and the clock agree.
    try {
      const tz = await this.api.get_setting('time_zone')
      if (tz) this.timeZone = tz
    } catch (e) {
      // keep the default ('local')
    }
    await this.checkIntegration()
    // Telemetry overlay is COSMOS-local, so it works even when the Vega
    // integration isn't connected yet.
    if (TLM_OVERLAY_ENABLED) {
      await this.loadTlmTargets()
      await this.restoreTlmOverlay()
    }
  },
  // The lanes element only exists once data is loaded (v-if), so the
  // ResizeObserver is (re)attached after any render that changes it.
  updated() {
    this.observeLaneWidth()
  },
  beforeUnmount() {
    clearInterval(this._clockTimer)
    if (this._laneResizeObserver) {
      this._laneResizeObserver.disconnect()
      this._laneResizeObserver = null
    }
    window.removeEventListener('mousemove', this.onPlotMouseMove)
    window.removeEventListener('mouseup', this.onPlotMouseUp)
    this.stopTelemetryStream()
    if (this._tlmSubscription) {
      this._tlmSubscription.unsubscribe()
      this._tlmSubscription = null
    }
    if (this._tlmCable) {
      this._tlmCable.disconnect()
      this._tlmCable = null
    }
  },
  methods: {
    // Keeps laneWidthPx current so slotMinutes can size the slices to the
    // pixels actually available. No-op until the lanes element exists.
    observeLaneWidth() {
      const el = this.$refs.plot
      if (!el || el === this._laneObserved) return
      if (this._laneResizeObserver) this._laneResizeObserver.disconnect()
      this._laneObserved = el
      this.laneWidthPx = el.getBoundingClientRect().width
      if (typeof ResizeObserver === 'undefined') return
      this._laneResizeObserver = new ResizeObserver((entries) => {
        const w = entries[0]?.contentRect?.width
        if (w && Math.abs(w - this.laneWidthPx) >= 1) this.laneWidthPx = w
      })
      this._laneResizeObserver.observe(el)
    },
    // Classifies the Vega connection on mount. The API key never passes
    // through the widget (the interface protocol injects the VEGA_API_KEY
    // COSMOS secret), so all it can do is read what the interface got back.
    // Fast path: APPROVED_ORGS already holds a 200 from the periodic poll ->
    // classify it without a round trip to Vega. Otherwise (never received,
    // or a stale success we can't vouch for) run the active probe.
    async checkIntegration() {
      try {
        const snap = await this.readPackets(INTEGRATION_SPEC)
        const ok = snap.APPROVED_ORGS
        if (stampOf(ok) > 0 && (Number(ok.HTTP_STATUS) || 0) === 200) {
          this.applyApprovedOrgs(ok.ORGANIZATIONS_JSON)
          return
        }
      } catch (e) {
        // fall through to the active probe
      }
      await this.retryIntegrationCheck()
    },
    // "Check again" button in the onboarding state (and the mount-time
    // fallback): sends GET_APPROVED_ORGS and waits for the answer to land.
    // A success lands in APPROVED_ORGS; any HTTP error lands in the shared
    // ERROR_RESPONSE packet instead (see ERROR_PACKET), so both are stamped
    // before the send and whichever advances first is the answer:
    //   APPROVED_ORGS advanced -> connected, or no_access when no orgs
    //   ERROR_RESPONSE advanced -> 401 missing_key, 403 no_access,
    //                              anything else (429, 5xx) unavailable
    //   neither within the timeout -> unavailable ("no response")
    async retryIntegrationCheck() {
      this.checkingIntegration = true
      this.integrationCheckError = ''
      try {
        const before = await this.readPackets(INTEGRATION_SPEC)
        const okStamp = stampOf(before.APPROVED_ORGS)
        const errStamp = stampOf(before[ERROR_PACKET])
        await this.api.cmd(
          'VEGA',
          'GET_APPROVED_ORGS',
          this.authOverride(),
          CMD_OPTS,
        )
        const deadline = Date.now() + INTEGRATION_CHECK_TIMEOUT_MS
        while (Date.now() < deadline) {
          await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))
          const snap = await this.readPackets(INTEGRATION_SPEC)
          const ok = snap.APPROVED_ORGS
          const err = snap[ERROR_PACKET]
          if (stampOf(ok) > okStamp) {
            this.applyApprovedOrgs(ok.ORGANIZATIONS_JSON)
            return
          }
          if (stampOf(err) > errStamp) {
            const status = Number(err.HTTP_STATUS) || 0
            const detail = shortErrorBody(err.BODY)
            if (status === 401) {
              this.setIntegrationState('missing_key', status, detail)
            } else if (status === 403) {
              this.setIntegrationState('no_access', status, detail)
            } else {
              this.setIntegrationState('unavailable', status, detail)
            }
            return
          }
        }
        // No response either way. With no key in this browser, the
        // interface protocol drops authenticated requests outright (it has
        // nothing to sign them with unless the VEGA_API_KEY secret exists),
        // so silence means "no key", not "Vega is down".
        this.setIntegrationState(
          this.savedApiKey ? 'unavailable' : 'missing_key',
        )
      } catch (e) {
        this.setIntegrationState('unavailable')
        this.integrationCheckError = `Could not check the Vega connection: ${e.message}`
      } finally {
        this.checkingIntegration = false
      }
    },
    // A 200 APPROVED_ORGS response: connected when it lists organizations,
    // otherwise the key works but has no approved org.
    applyApprovedOrgs(orgs) {
      this.organizations = orgs || []
      if (this.organizations.length === 0) {
        this.setIntegrationState('no_access', 200)
        return
      }
      this.setIntegrationState('connected', 200)
      // Setting this triggers the selectedOrgId watcher, which does the
      // actual workspace fetch.
      this.selectedOrgId = this.organizations[0].id
    },
    // --- The user's own Vega API key (browser-only) ---
    // Sent with every command as the OBFUSCATEd HTTP_HEADER_AUTHORIZATION
    // parameter. Absent -> the interface falls back to the VEGA_API_KEY secret.
    authOverride() {
      return this.savedApiKey
        ? { HTTP_HEADER_AUTHORIZATION: `Bearer ${this.savedApiKey}` }
        : {}
    },
    async saveApiKey() {
      const key = (this.apiKeyInput || '').trim()
      if (!key) return
      if (!key.startsWith('vgk_')) {
        this.saveKeyError =
          'Enter a Vega frontend API key - it starts with vgk_.'
        return
      }
      this.saveKeyError = ''
      this.savingKey = true
      try {
        this.savedApiKey = key
        try {
          localStorage.setItem(API_KEY_LS_KEY, key)
        } catch (e) {
          // storage blocked: the key still works for this page load
        }
        this.apiKeyInput = ''
        await this.retryIntegrationCheck()
        if (this.integrationState === 'missing_key') {
          this.saveKeyError =
            'Vega rejected that key (HTTP 401). Check it and try again.'
        }
      } finally {
        this.savingKey = false
      }
    },
    forgetApiKey() {
      this.savedApiKey = null
      try {
        localStorage.removeItem(API_KEY_LS_KEY)
      } catch (e) {
        // nothing stored
      }
      this.setIntegrationState('missing_key')
    },
    setIntegrationState(state, status = null, detail = '') {
      this.integrationState = state
      this.integrationStatus = status
      this.integrationDetail = detail
      this.notIntegrated = state !== 'connected'
    },
    // Click on a lane expands/collapses that band's chart. A click that was
    // actually the tail end of a drag-zoom must not toggle - onPlotMouseUp
    // flags drags and this consumes the flag.
    onLaneClick(band) {
      if (this._wasDrag) {
        this._wasDrag = false
        return
      }
      this.expandedBand = this.expandedBand === band ? null : band
    },
    // A plain click (not the tail of a drag-zoom) on a cell opens it: zoom
    // to that pass and expand that band's row. Clicking the open cell again
    // closes it (zoom out, collapse). A click outside any pass (in a gap)
    // falls back to the row toggle.
    onCellClick(band, e) {
      if (this._wasDrag) return
      // Locate the pass from the click itself, not the hover state (which
      // may be stale or cleared), so a click on a bar always resolves.
      let seg = null
      const rect = this.$refs.plot && this.$refs.plot.getBoundingClientRect()
      if (e && rect && rect.width) {
        const px = Math.min(Math.max(e.clientX - rect.left, 0), rect.width)
        const c =
          this.viewStart + (px / rect.width) * (this.viewEnd - this.viewStart)
        seg =
          this.segments.find((s) => c >= s.cstart && c < s.cstart + s.clen) ||
          null
      }
      if (!seg) {
        this.expandedBand = this.expandedBand === band ? null : band
        return
      }
      const range = [seg.cstart, seg.cstart + seg.clen]
      const sameZoom =
        this.zoomRange &&
        this.zoomRange[0] === range[0] &&
        this.zoomRange[1] === range[1]
      if (sameZoom && this.expandedBand === band) {
        this.zoomRange = null
        this.expandedBand = null
      } else {
        this.zoomRange = range
        this.expandedBand = band
      }
    },
    // --- Satellite telemetry overlay (COSMOS streaming) ---
    async loadTlmTargets() {
      try {
        const names = await this.api.get_target_names()
        this.tlmTargets = (names || []).filter((t) => t !== 'UNKNOWN')
      } catch (e) {
        this.tlmError = `Could not list targets: ${e.message}`
      }
    },
    async loadTlmPackets(target) {
      try {
        const names = await this.api.get_all_tlm_names(target)
        this.tlmPackets = names || []
      } catch (e) {
        this.tlmError = `Could not list packets: ${e.message}`
      }
    },
    async loadTlmItems(target, packet) {
      try {
        const def = await this.api.get_telemetry(target, packet)
        this.tlmItems = (def?.items || [])
          .map((i) => i.name)
          .filter((n) => !TLM_ITEM_BLOCKLIST.has(n))
      } catch (e) {
        this.tlmError = `Could not list items: ${e.message}`
      }
    },
    // Re-selects a previously chosen overlay item from localStorage. The
    // _restoringTlm flag keeps the cascading watchers from wiping the child
    // selections while we set all three levels programmatically.
    async restoreTlmOverlay() {
      let saved = null
      try {
        saved = JSON.parse(localStorage.getItem(TLM_OVERLAY_LS_KEY))
      } catch {
        return
      }
      if (!saved?.target || !saved.packet || !saved.item) return
      if (!this.tlmTargets.includes(saved.target)) return
      this._restoringTlm = true
      try {
        this.tlmTarget = saved.target
        await this.loadTlmPackets(saved.target)
        if (!this.tlmPackets.includes(saved.packet)) return
        this.tlmPacket = saved.packet
        await this.loadTlmItems(saved.target, saved.packet)
        if (!this.tlmItems.includes(saved.item)) return
        this.tlmItem = saved.item
      } finally {
        this._restoringTlm = false
      }
      if (this.tlmItem) this.restartTelemetryStream()
    },
    tlmSubscriptionKey(mode) {
      const base = `${mode}__TLM__${this.tlmTarget}__${this.tlmPacket}__${this.tlmItem}__CONVERTED`
      return mode === 'REDUCED_MINUTE' ? `${base}__AVG` : base
    },
    // Stops streaming the current item WITHOUT tearing down the channel
    // subscription. The subscription is deliberately persistent: anycable
    // rejects an immediate re-subscribe to the same channel identifier as
    // "Already subscribing" (see the workaround notes in js-common's
    // cable.js), which silently kills the channel - so item changes must be
    // 'remove'/'add' performs on one long-lived subscription, exactly like
    // TlmGrapher does. Full teardown happens only in beforeUnmount.
    stopTelemetryStream() {
      this._tlmStreamGen++
      if (this._tlmFallbackTimer) {
        clearTimeout(this._tlmFallbackTimer)
        this._tlmFallbackTimer = null
      }
      const keys = this._tlmActiveKeys || []
      if (this._tlmConnected && this._tlmSubscription && keys.length) {
        this._tlmSubscription.perform('remove', {
          scope: window.openc3Scope,
          token: localStorage.openc3Token,
          items: keys,
        })
      }
      this._tlmActiveKeys = []
    },
    restartTelemetryStream() {
      this.stopTelemetryStream()
      this._tlmBuckets = {}
      this.tlmVersion++
      this.tlmError = ''
      if (!this.tlmItem) return
      // Minute-reduced data first (72h fits in <=4320 points); fall back to
      // raw DECOM (bucketed client-side) if the reducer has nothing for this
      // item after TLM_REDUCED_FALLBACK_MS.
      this.subscribeTelemetry('REDUCED_MINUTE')
    },
    subscribeTelemetry(mode) {
      const gen = this._tlmStreamGen
      const key = this.tlmSubscriptionKey(mode)
      this._tlmActiveKeys = [key]
      this.ensureTlmSubscription()
      // perform() is only meaningful once the channel is confirmed; before
      // that the connected callback does the initial add for us.
      if (this._tlmConnected && this._tlmSubscription) {
        this.performTlmAdd()
      }
      if (mode === 'REDUCED_MINUTE') {
        this._tlmFallbackTimer = setTimeout(() => {
          if (gen !== this._tlmStreamGen) return
          if (Object.keys(this._tlmBuckets).length > 0) return
          // No reduced data for this item - swap to raw DECOM on the same
          // subscription (bucketed client-side in handleTlmBatch).
          this.stopTelemetryStream()
          this.subscribeTelemetry('DECOM')
        }, TLM_REDUCED_FALLBACK_MS)
      }
    },
    // Streams history from the chart window's start (today 00:00 UTC);
    // earlier data can't be drawn, so it isn't requested.
    performTlmAdd() {
      const keys = this._tlmActiveKeys || []
      if (!keys.length || !this._tlmSubscription) return
      this._tlmSubscription.perform('add', {
        scope: window.openc3Scope,
        token: localStorage.openc3Token,
        items: keys,
        start_time: this.day0StartMs * 1_000_000,
      })
    },
    // Creates the single StreamingChannel subscription this widget ever uses.
    ensureTlmSubscription() {
      if (this._tlmSubscription || this._tlmSubscribing) return
      this._tlmSubscribing = true
      if (!this._tlmCable) this._tlmCable = new Cable()
      this._tlmCable
        .createSubscription('StreamingChannel', window.openc3Scope, {
          received: (batch) => this.handleTlmBatch(batch),
          connected: () => {
            // Fires on the initial connect AND on automatic reconnects; both
            // times, (re-)add whatever item is currently selected. The
            // subscription handle is stored in the .then below, which can
            // resolve after connected fires - retry briefly rather than
            // silently never adding the item.
            this._tlmConnected = true
            const doAdd = () => {
              if (!this._tlmConnected) return
              if (!this._tlmSubscription) {
                setTimeout(doAdd, 100)
                return
              }
              this.performTlmAdd()
            }
            doAdd()
          },
          disconnected: () => {
            this._tlmConnected = false
          },
          rejected: () => {
            this._tlmConnected = false
            this.tlmError = 'Telemetry stream rejected'
          },
        })
        .then((subscription) => {
          this._tlmSubscription = subscription
          this._tlmSubscribing = false
        })
    },
    handleTlmBatch(batch) {
      const keys = this._tlmActiveKeys || []
      if (!keys.length || !Array.isArray(batch) || batch.length === 0) return
      const key = keys[0]
      let changed = false
      for (const sample of batch) {
        const timeNs = sample['__time']
        if (timeNs == null || !(key in sample)) continue
        const value = Number(sample[key])
        if (!Number.isFinite(value)) continue
        const idx = (timeNs / 1_000_000 - this.day0StartMs) / 60000
        if (idx < 0 || idx > this.totalMinutes) continue
        // Bucket to whole minutes (keep latest per bucket) so a raw DECOM
        // stream can't grow unbounded - the 72h window caps at 4320 buckets.
        this._tlmBuckets[Math.round(idx)] = [idx, value]
        changed = true
      }
      if (changed) this.tlmVersion++
    },
    formatTlmValue(v) {
      if (!Number.isFinite(v)) return String(v)
      const abs = Math.abs(v)
      if (abs >= 1000) return v.toFixed(0)
      if (abs >= 10) return v.toFixed(1)
      return Number(v.toPrecision(3)).toString()
    },
    // Compressed-coordinate helpers (see the PASS_GAP_PX block up top).
    idxToC(idx) {
      for (const seg of this.segments) {
        if (idx >= seg.startIdx && idx < seg.endIdx) {
          return seg.cstart + (idx - seg.startIdx)
        }
      }
      return null // minute falls in a removed between-pass gap
    },
    cToIdx(c) {
      for (const seg of this.segments) {
        if (c >= seg.cstart && c < seg.cstart + seg.clen) {
          // floor: the slice for minute N spans [N, N+1), so the cursor is
          // over slice N until it crosses into N+1's slot.
          return seg.startIdx + Math.floor(c - seg.cstart)
        }
      }
      return null
    },
    cToPct(c) {
      return ((c - this.viewStart) / (this.viewEnd - this.viewStart)) * 100
    },
    idxToPct(idx) {
      const c = this.idxToC(idx)
      return c === null ? -1000 : this.cToPct(c)
    },
    idxToDate(idx) {
      return new Date(this.day0StartMs + idx * 60000)
    },
    formatHM(date) {
      const p = zoneParts(date.getTime(), this.timeZone)
      return `${pad2(p.hh)}:${pad2(p.mm)}`
    },
    // Rounds a raw max up to a "nice" round number (1/2/5 x10^n) so y-axis
    // ticks land on sensible values instead of awkward fractions.
    niceMax(raw) {
      if (raw <= 0) return 4
      const magnitude = Math.pow(10, Math.floor(Math.log10(raw)))
      const residual = raw / magnitude
      let niceResidual
      if (residual <= 1) niceResidual = 1
      else if (residual <= 2) niceResidual = 2
      else if (residual <= 5) niceResidual = 5
      else niceResidual = 10
      return niceResidual * magnitude
    },
    // Interference level of a per-band count relative to that band's peak
    // in the loaded window, 0..1 - the input to both slice height and the
    // colour ramp.
    levelOf(count, band) {
      const max = this.bandMaxes[band] || 1
      return Math.min(1, Math.max(0, count / max))
    },
    // Builds one band's slices across every loaded day as RAMP_STEPS SVG
    // paths (one per ramp colour). Minutes are walked in slots of
    // slotMinutes; a slot takes its worst minute's count, so grouping never
    // hides a spike. Each slice is a SLICE_FILL-wide rect rising from the
    // baseline (CHART_H) in compressed x coordinates, drawn only inside
    // passes - the removed between-pass dead time never gets slices. A slot
    // that isn't covered, or has zero interference, draws nothing: on the
    // pass-compressed axis "no slice" already reads as "clean".
    // With a [c0, c1] range (compressed units) only the slots whose centre
    // falls inside it are built - used for the drag-zoom highlight.
    buildBandBars(band, range = null) {
      const slot = this.slotMinutes
      const d = new Array(RAMP_STEPS).fill('')
      for (const seg of this.segments) {
        for (let idx = seg.startIdx; idx < seg.endIdx; idx += slot) {
          const stop = Math.min(seg.endIdx, idx + slot)
          if (range) {
            const cx = seg.cstart + (idx - seg.startIdx) + (stop - idx) / 2
            if (cx < range[0] || cx > range[1]) continue
          }
          const g = this.sliceGeom(band, seg, idx, stop)
          if (g) d[g.step] += g.d
        }
      }
      return d
    },
    // Worst per-band count across the minutes [start, stop) - what a slot
    // shows, so grouping never hides a spike.
    slotCount(band, start, stop) {
      const entries = this.minuteEntries
      let count = 0
      for (let j = start; j < stop; j++) {
        const entry = entries[j]
        if (!entry || !entry.covered) continue
        const c = (entry.counts && entry.counts[band]) || 0
        if (c > count) count = c
      }
      return count
    },
    // Geometry of one slot's slice for a band: the path fragment, its ramp
    // step and level. null when there is nothing to draw. Each slice sits
    // centred in its slot, so the gap is split evenly on both sides and the
    // first/last slices keep the same margin from the box edges as from each
    // other; a short final slot (pass length not a multiple of slot) gets a
    // proportionally narrower slice, never one that spills past the pass
    // boundary into the next box.
    sliceGeom(band, seg, start, stop) {
      const count = this.slotCount(band, start, stop)
      if (!(count > 0)) return null
      const level = this.levelOf(count, band)
      const step = Math.round(level * (RAMP_STEPS - 1))
      const h = level * CHART_H
      const span = stop - start
      const inset = (span * (1 - SLICE_FILL)) / 2
      const w = (span * SLICE_FILL).toFixed(2)
      const x = (seg.cstart + (start - seg.startIdx) + inset).toFixed(2)
      // M x,top  h w  V baseline  h -w  Z : one slice, w minutes wide
      const d = `M${x},${(CHART_H - h).toFixed(1)}h${w}V${CHART_H}h-${w}Z`
      return { d, step, level, count }
    },
    // Click-drag on the chart to zoom into a narrower time window. The
    // underlying path data (in absolute minute coordinates) never changes -
    // zooming only narrows the SVG viewBox and rescales the axes, so it's
    // instant with no re-fetch.
    onPlotMouseDown(e) {
      this._wasDrag = false
      const rect = this.$refs.plot.getBoundingClientRect()
      this.dragStartPx = e.clientX - rect.left
      this.dragCurrentPx = this.dragStartPx
      window.addEventListener('mousemove', this.onPlotMouseMove)
      window.addEventListener('mouseup', this.onPlotMouseUp)
    },
    // Tracks the mouse for the hover crosshair/tooltip - separate from
    // onPlotMouseDown/Move/Up above, which only run during an active
    // click-drag zoom.
    onPlotHover(e) {
      if (this.dragStartPx !== null) return // mid drag-zoom, ignore
      const rect = this.$refs.plot.getBoundingClientRect()
      if (!rect.width) return
      const px = Math.min(Math.max(e.clientX - rect.left, 0), rect.width)
      const span = this.viewEnd - this.viewStart
      const c = this.viewStart + (px / rect.width) * span
      // null in a between-pass gap - no crosshair/tooltip there
      this.hoverIdx = this.cToIdx(c)
    },
    onPlotLeave() {
      this.hoverIdx = null
    },
    onPlotMouseMove(e) {
      if (this.dragStartPx === null) return
      const rect = this.$refs.plot.getBoundingClientRect()
      this.dragCurrentPx = Math.min(
        Math.max(e.clientX - rect.left, 0),
        rect.width,
      )
      // Only once it is really a drag: hide the hover crosshair/tooltip so
      // the selection highlight reads cleanly. A plain click keeps them.
      if (Math.abs(this.dragCurrentPx - this.dragStartPx) >= 4) {
        this.hoverIdx = null
      }
    },
    onPlotMouseUp() {
      window.removeEventListener('mousemove', this.onPlotMouseMove)
      window.removeEventListener('mouseup', this.onPlotMouseUp)
      if (this.dragStartPx === null) return
      const rect = this.$refs.plot.getBoundingClientRect()
      const startPx = Math.min(this.dragStartPx, this.dragCurrentPx)
      const endPx = Math.max(this.dragStartPx, this.dragCurrentPx)
      this.dragStartPx = null
      this.dragCurrentPx = null
      if (endPx - startPx < 4 || !rect.width) return // treat as a click, not a drag
      // The click event that trails this mouseup (if any - it only fires
      // when the press and release share an element) must not open a cell.
      // Cleared on a timer rather than by the click itself, so a drag that
      // ends elsewhere can't leave the flag set and swallow the NEXT click.
      this._wasDrag = true
      setTimeout(() => {
        this._wasDrag = false
      }, 0)
      const span = this.viewEnd - this.viewStart
      const newStart = this.viewStart + (startPx / rect.width) * span
      const newEnd = this.viewStart + (endPx / rect.width) * span
      if (newEnd - newStart < 5) return // guard against zooming to near-nothing
      this.zoomRange = [Math.round(newStart), Math.round(newEnd)]
    },
    resetZoom() {
      this.zoomRange = null
    },
    // Fetches the satellite/ground-station workspace AND per-satellite
    // forecast availability for whichever org is currently selected
    // (on-demand, not the periodic default-org poll), and resets everything
    // downstream (selected satellite/ground station, loaded forecast data,
    // zoom) since none of it is valid for a new org.
    async loadWorkspaceForCurrentOrg(orgId = this.selectedOrgId) {
      const requestId = (this.workspaceRequestId || 0) + 1
      this.workspaceRequestId = requestId
      this.satellites = []
      this.groundStations = []
      this.forecastAvailableBySatId = null
      this.selectedSatelliteId = null
      this.selectedGroundStationId = null
      this.dayDataByDate = {}
      this.zoomRange = null
      this.workspaceLoading = true
      this.errorText = ''
      try {
        const ws = await this.fetchWorkspaceForOrgWithRetry(orgId)
        if (
          requestId !== this.workspaceRequestId ||
          orgId !== this.selectedOrgId
        )
          return
        this.satellites = ws.satellites
        this.groundStations = ws.groundStations

        try {
          this.forecastAvailableBySatId =
            await this.fetchForecastAvailabilityForOrgWithRetry(orgId)
          if (
            requestId !== this.workspaceRequestId ||
            orgId !== this.selectedOrgId
          )
            return
        } catch (e) {
          // Non-fatal: the satellite picker just won't be sorted/disabled by
          // forecast availability if this lookup fails.
          this.forecastAvailableBySatId = null
        }
        if (
          requestId !== this.workspaceRequestId ||
          orgId !== this.selectedOrgId
        )
          return

        const firstAvailable = this.forecastAvailableBySatId
          ? this.satellites.find((s) => this.forecastAvailableBySatId[s.id])
          : null
        if (firstAvailable) {
          this.selectedSatelliteId = firstAvailable.id
        } else if (this.satellites.length > 0) {
          this.selectedSatelliteId = this.satellites[0].id
        }
        if (this.groundStations.length > 0) {
          this.selectedGroundStationId = this.groundStations[0].id
        }

        const orgLabel = this.selectedOrg
          ? this.selectedOrg.name
          : 'this organization'
        if (this.satellites.length === 0 || this.groundStations.length === 0) {
          this.errorText = `${orgLabel} has no satellites/ground stations in its workspace.`
        } else if (this.forecastAvailableBySatId && !firstAvailable) {
          this.errorText = `No satellites in ${orgLabel} have a forecast available yet.`
        }
      } catch (e) {
        if (
          requestId !== this.workspaceRequestId ||
          orgId !== this.selectedOrgId
        )
          return
        this.errorText = `Failed to load workspace for this organization: ${e.message}`
      } finally {
        if (requestId === this.workspaceRequestId) this.workspaceLoading = false
      }
    },
    async fetchForecastAvailabilityForOrgWithRetry(orgId, attempts = 4) {
      let lastError
      for (let i = 0; i < attempts; i++) {
        try {
          return await this.fetchForecastAvailabilityForOrg(orgId)
        } catch (e) {
          lastError = e
          // The interface can't fix a 401/403/404 by reconnecting.
          if (this.isFinalHttpError(e)) throw e
          if (i < attempts - 1) {
            await this.waitForInterfaceConnected(20000)
          }
        }
      }
      throw lastError
    },
    // Sends GET_FORECASTING_SUMMARY with HTTP_PATH overridden to the given
    // org, then waits for VEGA FORECASTING_SUMMARY to carry a fresh response
    // whose ORG_ID confirms it reflects THIS request (same reasoning as
    // fetchWorkspaceForOrg - the periodic default-org poll keeps writing to
    // this same packet). Returns a { [satelliteId]: forecastAvailable } map
    // built from the full satellites array.
    async fetchForecastAvailabilityForOrg(orgId) {
      const { status, values } = await this.requestPacket({
        command: 'GET_FORECASTING_SUMMARY',
        params: {
          HTTP_PATH: `/api/v1/frontend/organizations/${orgId}/forecasting/summary`,
        },
        packet: 'FORECASTING_SUMMARY',
        echo: ['ORG_ID'],
        matches: (v) => Number(v.ORG_ID) === Number(orgId),
        payload: ['SATELLITES_JSON'],
        timeoutMs: 15000,
        label: `forecasting summary of org ${orgId}`,
      })
      if (status >= 300) {
        throw new Error(`HTTP ${status} for org ${orgId} forecasting summary`)
      }
      const map = {}
      for (const sat of values.SATELLITES_JSON || []) {
        map[sat.id] = !!sat.forecast_available
      }
      return map
    },
    async fetchWorkspaceForOrgWithRetry(orgId, attempts = 4) {
      let lastError
      for (let i = 0; i < attempts; i++) {
        try {
          return await this.fetchWorkspaceForOrg(orgId)
        } catch (e) {
          lastError = e
          // The interface can't fix a 401/403/404 by reconnecting.
          if (this.isFinalHttpError(e)) throw e
          if (i < attempts - 1) {
            await this.waitForInterfaceConnected(20000)
          }
        }
      }
      throw lastError
    },
    // Sends GET_WORKSPACE with HTTP_PATH overridden to the given org, then
    // waits for VEGA WORKSPACE to carry a fresh response whose ORG_ID confirms
    // it reflects THIS request - needed because the periodic poll (plugin's
    // default vega_org_id) keeps writing to this same packet in the
    // background regardless.
    async fetchWorkspaceForOrg(orgId) {
      const { status, values } = await this.requestPacket({
        command: 'GET_WORKSPACE',
        params: {
          HTTP_PATH: `/api/v1/frontend/organizations/${orgId}/workspace`,
        },
        packet: 'WORKSPACE',
        echo: ['ORG_ID'],
        matches: (v) => Number(v.ORG_ID) === Number(orgId),
        payload: ['SATELLITES_JSON', 'GROUND_STATIONS_JSON'],
        timeoutMs: 15000,
        label: `workspace of org ${orgId}`,
      })
      if (status >= 300) {
        throw new Error(`HTTP ${status} for org ${orgId}`)
      }
      return {
        satellites: values.SATELLITES_JSON || [],
        groundStations: values.GROUND_STATIONS_JSON || [],
      }
    },
    dayCacheKey(satId, gsId, day) {
      return `${satId}|${gsId}|${day.date}|${day.past ? 'h' : 'f'}`
    },
    // force=true (the Refresh button) bypasses the cache for the visible
    // window. Otherwise sliding the window only fetches days not already in
    // the per-(satellite, station, day) cache: measured history is immutable
    // so it caches for the session; today/forecast days expire after
    // FORECAST_CACHE_TTL_MS since the forecast (and today's elapsed portion)
    // keeps changing.
    async loadForecast(force = false) {
      if (!this.selectedSatelliteId || !this.selectedGroundStationId) return
      // Generation counter: selection changes can start a new load while an
      // old one is mid-flight; the stale load must stop writing so the chart
      // never mixes two satellites' data.
      const gen = ++this._forecastGen
      this.errorText = ''
      this.zoomRange = null
      const satId = this.selectedSatelliteId
      const gsId = this.selectedGroundStationId
      const cached = {}
      const missingPast = []
      const missingForecast = []
      const nowMs = Date.now()
      for (const day of this.utcFetchDays) {
        const hit = this._dayCache[this.dayCacheKey(satId, gsId, day)]
        const fresh =
          hit && (day.past || nowMs - hit.at < FORECAST_CACHE_TTL_MS)
        if (force !== true && fresh) {
          cached[day.date] = hit.data
        } else {
          ;(day.past ? missingPast : missingForecast).push(day)
        }
      }
      // Cached days render immediately; only the rest are fetched.
      this.dayDataByDate = cached
      const total = missingForecast.length + (missingPast.length ? 1 : 0)
      if (total === 0) return
      this.loading = true
      let done = 0
      const failures = []
      try {
        if (missingPast.length) {
          this.progressText = `Loading history (0/${total})`
          try {
            await this.loadHistory(satId, gsId, gen, missingPast)
          } catch (e) {
            failures.push(`history: ${e.message}`)
          }
          if (gen !== this._forecastGen) return
          done++
        }
        for (const day of missingForecast) {
          this.progressText = `Loading ${day.date} (${done}/${total})`
          // Small pacing gap between requests - spreads the batch out to
          // reduce the odds of tripping whatever's causing the occasional
          // Net::ReadTimeout blips (likely rate limiting on rapid bursts).
          if (done > 0) {
            await new Promise((resolve) => setTimeout(resolve, 600))
          }
          try {
            const dayData = await this.fetchDayDetailWithRetry(
              satId,
              gsId,
              day.date,
            )
            if (gen !== this._forecastGen) return
            this._dayCache[this.dayCacheKey(satId, gsId, day)] = {
              at: Date.now(),
              data: dayData,
            }
            this.dayDataByDate = { ...this.dayDataByDate, [day.date]: dayData }
          } catch (e) {
            if (gen !== this._forecastGen) return
            failures.push(`${day.date}: ${e.message}`)
          }
          done++
        }
        this.progressText = ''
        this.errorText = failures.length
          ? `${failures.length}/${total} requests failed to load (results shown for the rest): ${failures.join('; ')}`
          : ''
      } finally {
        if (gen === this._forecastGen) this.loading = false
      }
    },
    // Calendar-day info for the day `offset` days from today in the display
    // zone (see the Time zone block up top).
    dayInfo(offset) {
      const tz = this.timeZone
      const now = zoneParts(Date.now(), tz)
      const startMs = zoneMidnightMs(now.y, now.m, now.d + offset, tz)
      // Noon is safely inside the day whatever DST does at its edges.
      const p = zoneParts(startMs + 12 * 3600000, tz)
      return {
        date: `${p.y}-${pad2(p.m + 1)}-${pad2(p.d)}`,
        startMs,
        weekday: p.wd,
        display: `${MONTHS[p.m]} ${p.d}`,
        past: offset < 0,
      }
    },
    // Moves the window to the given day offset (clamped to the 30-day
    // history / 72h forecast range) and reloads.
    setWindowOffset(offset) {
      const next = Math.min(
        MAX_FORWARD_OFFSET,
        Math.max(-MAX_BACK_DAYS, Number(offset)),
      )
      if (!Number.isFinite(next) || next === this.windowOffsetDays) return
      this.windowOffsetDays = next
      this.zoomRange = null
      if (this.selectedSatelliteId && this.selectedGroundStationId) {
        this.loadForecast()
      }
    },
    dateAfter(dateStr) {
      return new Date(new Date(`${dateStr}T00:00:00Z`).getTime() + 86400000)
        .toISOString()
        .slice(0, 10)
    },
    // Fetches the whole past region's measured interference in one
    // GET_HISTORY request and converts it into the SAME per-day/per-minute
    // shape GET_DAY_DETAIL produces (covered + per-band counts), so past
    // days render through the identical per-band bar pipeline as the forecast:
    // same severity colours, legend toggles and tooltip. A 404/timeout
    // is non-fatal upstream - the chart just shows forecast only.
    async loadHistory(
      satelliteId,
      groundStationId,
      gen,
      pastDays,
      attempts = 3,
    ) {
      if (!pastDays?.length) return
      const startIso = `${pastDays[0].date}T00:00:00Z`
      const endIso = `${this.dateAfter(pastDays[pastDays.length - 1].date)}T00:00:00Z`
      let lastError
      for (let i = 0; i < attempts; i++) {
        try {
          const timeseries = await this.fetchHistory(
            satelliteId,
            groundStationId,
            startIso,
            endIso,
          )
          if (gen !== undefined && gen !== this._forecastGen) return
          // Full 1440-minute skeleton per day (covered=false plots as the
          // zero baseline), overridden by the visible minutes we got back.
          const byDate = {}
          for (const day of pastDays) {
            const dayStart = new Date(`${day.date}T00:00:00Z`).getTime()
            byDate[day.date] = Array.from({ length: 1440 }, (_, m) => ({
              timestamp: new Date(dayStart + m * 60000).toISOString(),
              covered: false,
              counts: {},
            }))
          }
          for (const point of timeseries) {
            const date = (point.timestamp || '').slice(0, 10)
            const minutes = byDate[date]
            if (!minutes) continue
            const m = Math.round(
              (new Date(point.timestamp).getTime() -
                new Date(`${date}T00:00:00Z`).getTime()) /
                60000,
            )
            if (m < 0 || m >= 1440) continue
            minutes[m] = {
              timestamp: minutes[m].timestamp,
              covered: true,
              counts: point.counts || {},
            }
          }
          const merged = {}
          for (const day of pastDays) {
            const dayData = {
              minutes: byDate[day.date],
              toneWarningMin: 1,
              toneHighMin: 10,
            }
            merged[day.date] = dayData
            // Measured history is immutable - cache it for the session.
            this._dayCache[
              this.dayCacheKey(satelliteId, groundStationId, day)
            ] = { at: Date.now(), data: dayData }
          }
          this.dayDataByDate = { ...this.dayDataByDate, ...merged }
          return
        } catch (e) {
          lastError = e
          // The interface can't fix a 401/403/404 by reconnecting.
          if (this.isFinalHttpError(e)) throw e
          if (i < attempts - 1) {
            await this.waitForInterfaceConnected(20000)
          }
        }
      }
      throw lastError
    },
    // Sends GET_HISTORY then waits for VEGA HISTORY to carry a fresh response
    // to this exact request (matched by satellite + ground station + range
    // start), mirroring fetchDayDetail. A non-2xx response (e.g. 404 when no
    // run covers the range) lands in ERROR_RESPONSE and is thrown as
    // `HTTP 404 for history` - callers treat that as "no history available",
    // not a hard failure.
    async fetchHistory(satelliteId, groundStationId, startIso, endIso) {
      const { status, values } = await this.requestPacket({
        command: 'GET_HISTORY',
        params: {
          HTTP_PATH: `/api/v1/frontend/organizations/${this.selectedOrgId}/forecasting/history`,
          HTTP_QUERY_SATELLITE_ID: satelliteId,
          HTTP_QUERY_GROUND_STATION_ID: groundStationId,
          HTTP_QUERY_START_TIME: startIso,
          HTTP_QUERY_END_TIME: endIso,
        },
        packet: 'HISTORY',
        echo: ['SATELLITE_ID', 'GROUND_STATION_ID', 'START_TIME'],
        matches: (v) =>
          Number(v.SATELLITE_ID) === Number(satelliteId) &&
          Number(v.GROUND_STATION_ID) === Number(groundStationId) &&
          v.START_TIME === startIso,
        payload: ['TIMESERIES_JSON'],
        timeoutMs: 20000,
        label: 'history (range may have no coverage)',
      })
      if (status >= 300) {
        throw new Error(`HTTP ${status} for history`)
      }
      return values.TIMESERIES_JSON || []
    },
    // Wraps fetchDayDetail with retries. A request to admin.vega.space can
    // occasionally hang past the interface's read timeout (rate limiting /
    // transient slowness) - when that happens COSMOS disconnects VEGA_INT,
    // which then fails every subsequent command instantly with "Interface
    // not connected" until it reconnects (a few seconds later, automatic).
    // So on failure we explicitly wait for VEGA_INT to report CONNECTED
    // again before retrying, instead of blindly retrying into a still-dead
    // interface.
    async fetchDayDetailWithRetry(
      satelliteId,
      groundStationId,
      date,
      attempts = 4,
    ) {
      let lastError
      for (let i = 0; i < attempts; i++) {
        try {
          return await this.fetchDayDetail(satelliteId, groundStationId, date)
        } catch (e) {
          lastError = e
          // The interface can't fix a 401/403/404 by reconnecting.
          if (this.isFinalHttpError(e)) throw e
          if (i < attempts - 1) {
            await this.waitForInterfaceConnected(20000)
          }
        }
      }
      throw lastError
    },
    // Polls get_all_interface_info for VEGA_INT's state, returning as soon as
    // it's CONNECTED (or immediately if it already is).
    async waitForInterfaceConnected(timeoutMs) {
      const deadline = Date.now() + timeoutMs
      while (Date.now() < deadline) {
        try {
          const info = await this.api.get_all_interface_info()
          const row = info.find((r) => r[0] === 'VEGA_INT')
          if (row && row[1] === 'CONNECTED') return
        } catch (e) {
          // ignore transient errors checking status, just keep polling
        }
        await new Promise((resolve) => setTimeout(resolve, 500))
      }
    },
    // Reads items from one or more VEGA packets in a single get_tlm_values
    // round trip (it takes TGT__PKT__ITEM__TYPE keys - from any packets - and
    // returns one [value, limitsState] pair per key, in order).
    // spec = { PACKET: [ITEM, ...] }; returns { PACKET: { ITEM: value } }.
    async readPackets(spec) {
      const keys = []
      for (const [packet, items] of Object.entries(spec)) {
        for (const item of items) keys.push([packet, item])
      }
      const rows = await this.api.get_tlm_values(
        keys.map(([packet, item]) => `VEGA__${packet}__${item}__CONVERTED`),
      )
      const out = {}
      keys.forEach(([packet, item], i) => {
        if (!out[packet]) out[packet] = {}
        out[packet][item] = rows?.[i]?.[0] ?? null
      })
      return out
    },
    async readPacket(packet, items) {
      return (await this.readPackets({ [packet]: items }))[packet]
    },
    // Errors an HTTP failure needs no retry for: the request itself is what
    // Vega rejected (bad key, no access, nothing at that path), as opposed to
    // a transport failure or timeout that a reconnected interface may fix.
    isFinalHttpError(e) {
      return [401, 403, 404].includes(e?.status)
    },
    // Sends `command` and polls until its answer is in the CVT. A success
    // lands in `packet`; an HTTP error lands in ERROR_RESPONSE instead (see
    // ERROR_PACKET), so both are stamped BEFORE the send and watched
    // together in one call per poll.
    // Success requires a response that (a) arrived after the send and
    // (b) echoes this request (`matches` over the `echo` items). Both checks
    // matter: the echo alone would accept the previous response when an
    // identical request is repeated (e.g. today's day re-fetched after the
    // forecast cache expires), and the timestamp alone would accept the
    // periodic default-org poll's response when it happens to land first.
    // Once matched, the `payload` items are read in one more call and
    // re-checked against the same timestamp, so a response landing in
    // between can't be mixed in.
    // An ERROR_RESPONSE that advanced past its stamp throws immediately with
    // `error.status` set (rather than burning the whole timeout). Caveat:
    // ERROR_RESPONSE is shared by every VEGA command, including the
    // background periodic polls - one of those failing in the same window
    // would be misattributed to this request. Accepted: stamp-before-send is
    // the best available filter without per-command error packets.
    // Resolves { status, values } (values = echo + payload items).
    async requestPacket({
      command,
      params,
      packet,
      echo,
      matches,
      payload,
      timeoutMs,
      label,
    }) {
      const sentAt = Date.now()
      const before = await this.readPackets({
        [packet]: ['RECEIVED_TIMESECONDS'],
        [ERROR_PACKET]: ['RECEIVED_TIMESECONDS'],
      })
      const stamp = stampOf(before[packet])
      const errStamp = stampOf(before[ERROR_PACKET])
      await this.api.cmd(
        'VEGA',
        command,
        { ...this.authOverride(), ...params },
        CMD_OPTS,
      )
      const pollSpec = {
        [packet]: ['RECEIVED_TIMESECONDS', 'HTTP_STATUS', ...echo],
        [ERROR_PACKET]: ERROR_ITEMS,
      }
      const deadline = Date.now() + timeoutMs
      while (Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))
        const snap = await this.readPackets(pollSpec)
        const head = snap[packet]
        const received = stampOf(head)
        if (received > stamp && matches(head)) {
          const body = await this.readPacket(packet, [
            'RECEIVED_TIMESECONDS',
            ...payload,
          ])
          // A newer response displaced ours between the two reads - keep
          // polling rather than returning a mismatched body.
          if (stampOf(body) !== received) continue
          return {
            status: Number(head.HTTP_STATUS) || 0,
            values: { ...head, ...body },
          }
        }
        const err = snap[ERROR_PACKET]
        if (stampOf(err) > errStamp) {
          const status = Number(err.HTTP_STATUS) || 0
          const detail = shortErrorBody(err.BODY)
          const error = new Error(
            `HTTP ${status} for ${label}${detail ? `: ${detail}` : ''}`,
          )
          error.status = status
          throw error
        }
      }
      throw new Error(
        `Timed out waiting for ${label} (sent ${Date.now() - sentAt}ms ago)`,
      )
    },

    // Sends GET_DAY_DETAIL then waits for VEGA DAY_DETAIL to carry a FRESH
    // response to this exact request (matched by satellite + ground station
    // + date), since HTTP responses land asynchronously via the interface ->
    // decom pipeline. HTTP_PATH is overridden to embed the currently-selected
    // org id - GET_DAY_DETAIL's command definition only bakes in the plugin's
    // default vega_org_id, so this is what lets the widget query ANY org the
    // API key has approved access to, not just the one the plugin was
    // installed with.
    async fetchDayDetail(satelliteId, groundStationId, date) {
      const { status, values } = await this.requestPacket({
        command: 'GET_DAY_DETAIL',
        params: {
          HTTP_PATH: `/api/v1/frontend/organizations/${this.selectedOrgId}/forecasting/day_detail`,
          HTTP_QUERY_SATELLITE_ID: satelliteId,
          HTTP_QUERY_GROUND_STATION_ID: groundStationId,
          HTTP_QUERY_DATE: date,
        },
        packet: 'DAY_DETAIL',
        echo: ['SATELLITE_ID', 'GROUND_STATION_ID', 'DATE'],
        matches: (v) =>
          Number(v.SATELLITE_ID) === Number(satelliteId) &&
          Number(v.GROUND_STATION_ID) === Number(groundStationId) &&
          v.DATE === date,
        payload: ['MINUTES_JSON', 'TONE_WARNING_MIN', 'TONE_HIGH_MIN'],
        timeoutMs: 15000,
        label: date,
      })
      if (status >= 300) {
        throw new Error(`HTTP ${status} for ${date}`)
      }
      return {
        minutes: values.MINUTES_JSON || [],
        toneWarningMin: Number(values.TONE_WARNING_MIN ?? 1),
        toneHighMin: Number(values.TONE_HIGH_MIN ?? 10),
      }
    },
  },
}
</script>

<style lang="scss" scoped>
.timeline-widget {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 8px;
  min-width: 700px;
  color: var(--v-theme-on-surface, inherit);
}
.controls-col {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 8px;
}
.controls-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.select-label {
  font-size: 11px;
  letter-spacing: 0.15em;
  opacity: 0.6;
  white-space: nowrap;
}
.status-text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  opacity: 0.7;
}
.progress-text {
  font-size: 12px;
  opacity: 0.7;
}
.error-text {
  font-size: 12px;
  color: #e57373;
}

// Band toggle chips are plain text now that colour encodes severity rather
// than band; the ramp legend next to them explains the slice colours
.legend-key {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 8px;
}
.legend-chip {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  border-radius: 999px;
  border: 1px solid rgba(128, 128, 128, 0.3);
  background: transparent;
  color: inherit;
  font-size: 12px;
  letter-spacing: 0.03em;
  cursor: pointer;
  transition: opacity 0.15s;
}
.legend-chip.inactive {
  opacity: 0.35;
}
.chip-swatch {
  display: block;
  overflow: visible;
}
.ramp-legend {
  display: flex;
  align-items: center;
  justify-content: flex-start;
  gap: 10px;
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid rgba(128, 128, 128, 0.25);
  font-size: 11px;
  opacity: 0.8;
  white-space: nowrap;
}
.tone-swatch {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 2px;
  flex: none;
}
.ramp-swatch {
  display: inline-block;
  width: 110px;
  height: 8px;
  border-radius: 2px;
  flex: none;
}
.asi-info-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  margin-left: 14px;
  padding: 2px 8px;
  border: none;
  border-radius: 999px;
  background: transparent;
  color: #4fc3f7;
  font-size: 11px;
  cursor: pointer;
}
.asi-info-btn:hover {
  text-decoration: underline;
}
.asi-info-title {
  font-size: 18px;
}
.asi-info-body {
  font-size: 14px;
  line-height: 1.5;
}
.asi-info-body h4 {
  margin: 14px 0 6px;
  font-size: 13px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.75;
}
.asi-info-body p,
.asi-info-body li {
  margin-bottom: 8px;
}
.asi-info-body ol,
.asi-info-body ul {
  padding-left: 22px;
}
.asi-info-body code {
  font-size: 12px;
}
.asi-info-note {
  margin-top: 12px;
  padding-top: 10px;
  border-top: 1px solid rgba(128, 128, 128, 0.3);
  opacity: 0.8;
}
.hover-tooltip-tone {
  margin-left: 6px;
  font-size: 10px;
  opacity: 0.75;
  letter-spacing: 0.04em;
}
/* Onboarding: the user's own API key */
.onboarding-keyform {
  margin: 14px 0 6px;
  max-width: 520px;
}
.onboarding-keylabel {
  display: block;
  font-size: 11px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.7;
  margin-bottom: 6px;
}
.onboarding-keyrow {
  display: flex;
  gap: 8px;
}
.onboarding-input {
  flex: 1;
  min-width: 0;
  padding: 8px 10px;
  border-radius: 6px;
  border: 1px solid rgba(128, 128, 128, 0.4);
  background: rgba(0, 0, 0, 0.25);
  color: inherit;
  font: inherit;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}
.onboarding-save {
  padding: 8px 14px;
  border-radius: 6px;
  border: 1px solid rgba(79, 195, 247, 0.6);
  background: rgba(79, 195, 247, 0.15);
  color: #4fc3f7;
  font: inherit;
  cursor: pointer;
}
.onboarding-save:disabled {
  opacity: 0.45;
  cursor: default;
}
.onboarding-keystatus,
.onboarding-keynote {
  margin-top: 8px;
  font-size: 12px;
  opacity: 0.75;
}
.onboarding-forget {
  margin-left: 6px;
  padding: 1px 8px;
  border-radius: 999px;
  border: 1px solid rgba(128, 128, 128, 0.4);
  background: transparent;
  color: inherit;
  font-size: 11px;
  cursor: pointer;
}
.reset-zoom-btn {
  padding: 3px 10px;
  border-radius: 999px;
  border: 1px solid rgba(79, 195, 247, 0.5);
  background: transparent;
  color: #4fc3f7;
  font-size: 12px;
  cursor: pointer;
  margin-left: 4px;
}

// Chart: y-axis labels | plot area (gridlines + svg lines), x-axis below
.chart-wrap {
  display: grid;
  grid-template-columns: 54px 1fr;
  grid-template-rows: auto 34px;
  column-gap: 6px;
}
.chart-wrap.has-overlay {
  grid-template-columns: 54px 1fr 60px;
}
.y-axis-right {
  grid-column: 3;
  grid-row: 1;
  position: relative;
  height: 240px;
}
.y-tick-right {
  position: absolute;
  left: 4px;
  transform: translateY(50%);
  font-size: 10px;
  opacity: 0.7;
}
.y-axis-label-right {
  position: absolute;
  right: 0;
  top: 50%;
  transform: translateY(-50%);
  writing-mode: vertical-rl;
  font-size: 10px;
  letter-spacing: 0.08em;
  opacity: 0.5;
}
.hover-tooltip-tlm {
  border-top: 1px solid rgba(128, 128, 128, 0.35);
  padding-top: 3px;
  margin-top: 3px;
}
.y-axis {
  grid-column: 1;
  grid-row: 1;
  position: relative;
  height: 240px;
}
.y-tick {
  position: absolute;
  right: 4px;
  transform: translateY(50%);
  font-size: 10px;
  opacity: 0.6;
  white-space: nowrap;
}
.y-axis-label {
  position: absolute;
  left: 2px;
  top: 50%;
  transform: translateY(-50%) rotate(180deg);
  writing-mode: vertical-rl;
  font-size: 10px;
  letter-spacing: 0.08em;
  opacity: 0.5;
  white-space: nowrap;
}
.chart-plot {
  grid-column: 2;
  grid-row: 1;
  position: relative;
  height: 240px;
  border: 1px solid rgba(128, 128, 128, 0.2);
  border-radius: 4px;
  overflow: hidden;
  cursor: crosshair;
  user-select: none;
}
.y-gridline {
  position: absolute;
  left: 0;
  right: 0;
  height: 1px;
  background: rgba(128, 128, 128, 0.15);
}
.day-gridline {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(128, 128, 128, 0.2);
}
.lines-svg {
  width: 100%;
  height: 100%;
  display: block;
}
.drag-selection {
  position: absolute;
  top: 0;
  bottom: 0;
  /* No tint: the selected slices are already lit and the rest dimmed, so
     the overlay only needs edges */
  border-left: 1px solid rgba(79, 195, 247, 0.7);
  border-right: 1px solid rgba(79, 195, 247, 0.7);
  pointer-events: none;
}
.hover-line {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(255, 255, 255, 0.55);
  pointer-events: none;
}
/* --- Per-band lanes --- */
.lanes-wrap {
  display: flex;
  flex-direction: column;
}
.lanes-body {
  display: flex;
}
.lanes-labels {
  width: 48px;
  flex: none;
  display: flex;
  flex-direction: column;
}
.lane-label {
  position: relative;
  height: 46px;
  flex: none;
  display: flex;
  /* bottom-aligned so the name sits on the lane's zero baseline, where the
     trace actually lives, instead of floating mid-lane */
  align-items: flex-end;
  justify-content: flex-start;
  padding-right: 6px;
  padding-bottom: 3px;
  margin-bottom: 8px; /* LANE_GAP_PX - keeps labels level with the rows */
  cursor: pointer;
  transition: height 0.15s ease;
}
.lane-label:last-child {
  margin-bottom: 0;
}
.lane-label .lane-name {
  opacity: 0.75;
  transition: opacity 0.1s ease;
}
.lane-label.hovered .lane-name {
  opacity: 1;
  font-weight: 600;
}
.lane-label.expanded {
  height: 220px;
}
.lane-label.expanded .lane-name {
  display: none; /* the expanded lane shows its name in .lane-title instead */
}
.lane-name {
  font-size: 11px;
  letter-spacing: 0.06em;
}
.lane-tick {
  position: absolute;
  right: 8px;
  font-size: 9px;
  opacity: 0.6;
  transform: translateY(50%);
}
.lanes-plots {
  position: relative;
  flex: 1;
  min-width: 0;
  cursor: crosshair;
  overflow: hidden;
}
.lane-plot {
  position: relative;
  height: 46px;
  margin-bottom: 8px; /* LANE_GAP_PX */
  transition: height 0.15s ease;
}
.lane-plot:last-child {
  margin-bottom: 0;
}
/* Grid cells: one outlined box per (pass, band), stacked to mirror the lane
   rows exactly (same heights, same row gap). The lanes draw no lines of
   their own, so nothing crosses the gaps. */
.pass-box {
  position: absolute;
  top: 0;
  bottom: 0;
  pointer-events: none;
  display: flex;
  flex-direction: column;
}
.pass-cell {
  height: 46px;
  flex: none;
  box-sizing: border-box;
  margin-bottom: 8px; /* LANE_GAP_PX */
  border: 1px solid rgba(128, 128, 128, 0.3);
  border-radius: 3px;
  transition: height 0.15s ease;
}
.pass-cell.expanded {
  height: 220px;
}
.pass-cell.active {
  border-color: rgba(255, 255, 255, 0.75);
}
.pass-cell.placeholder {
  border-color: transparent;
}
.empty-row {
  position: absolute;
  left: 0;
  right: 0;
  box-sizing: border-box;
  border: 1px solid rgba(128, 128, 128, 0.3);
  border-radius: 3px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  opacity: 0.45;
  pointer-events: none;
}
.cell-highlight {
  position: absolute;
  box-sizing: border-box;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.08);
  pointer-events: none;
}
.pass-cell:last-child {
  margin-bottom: 0;
}
.lane-plot.expanded {
  height: 220px;
}
.hover-tooltip-row-active {
  font-weight: 700;
}
.lane-svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  display: block;
}
.lane-title {
  position: absolute;
  top: 4px;
  left: 8px;
  font-size: 10px;
  letter-spacing: 0.08em;
  opacity: 0.55;
  pointer-events: none;
}
.x-axis-row {
  display: flex;
  height: 16px;
}
.pass-row {
  display: flex;
  height: 18px;
}
.pass-track {
  position: relative;
  flex: 1;
  min-width: 0;
}
.pass-label {
  position: absolute;
  top: 0;
  transform: translateX(-50%);
  font-size: 10px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.9;
  white-space: nowrap;
}
.x-axis-spacer {
  width: 48px; /* .lanes-labels */
  flex: none;
}
.x-axis-row .x-axis {
  position: relative;
  flex: 1;
  min-width: 0;
  overflow: hidden;
}

.window-nav {
  display: flex;
  align-items: center;
  gap: 8px;
}
.window-nav-right {
  margin-left: auto;
  min-width: 0;
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
}
.quick-days {
  /* Drawn with the same Astro variables COSMOS applies to v-select
     fieldsets, so it reads as one of the fields above */
  height: 40px;
  border: 1px solid var(--color-border-interactive-muted);
  border-radius: 4px;
  background-color: var(--color-background-base-default);
  color: var(--color-text-interactive-default);
  overflow: hidden;
}
.quick-days .v-btn {
  height: 100% !important;
  border-radius: 0;
  text-transform: none;
  letter-spacing: normal;
  font-size: 14px;
  font-weight: 400;
  padding: 0 16px;
  color: var(--color-text-interactive-default) !important;
}
.quick-days .v-btn + .v-btn {
  border-left: 1px solid var(--color-border-interactive-muted);
}
.quick-days .v-btn.v-btn--active {
  background-color: var(--color-background-surface-selected);
}
.cal-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  height: 40px;
  padding: 0 12px;
  border: 1px solid var(--color-border-interactive-muted);
  border-radius: 4px;
  background-color: var(--color-background-base-default);
  color: var(--color-text-interactive-default);
  cursor: pointer;
  font-size: 14px;
}
.cal-btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.cal-list {
  min-width: 240px;
}
.cal-weekday {
  display: inline-block;
  width: 3.2em;
  font-size: 11px;
  letter-spacing: 0.06em;
  opacity: 0.6;
}
.day-kind {
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  opacity: 0.6;
  margin-left: 12px;
}
.day-kind.today {
  opacity: 1;
  color: #4fc3f7;
}
.day-kind.forecast {
  opacity: 0.85;
}
/* Vertical divider between passes on the compressed x axis */
.no-passes-note {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  opacity: 0.55;
  pointer-events: none;
}
/* Divider between measured history (left) and forecast (right) */
.now-line {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 0;
  border-left: 1px dashed rgba(255, 255, 255, 0.35);
  pointer-events: none;
}
.hover-tooltip {
  position: absolute;
  top: 6px;
  transform: translateX(8px);
  min-width: 130px;
  padding: 8px 10px;
  border-radius: 6px;
  background: rgba(10, 20, 30, 0.95);
  border: 1px solid rgba(128, 128, 128, 0.3);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
  pointer-events: none;
  z-index: 5;
  font-size: 12px;
  color: #fff;
}
.hover-tooltip.flip {
  transform: translateX(calc(-100% - 8px));
}
.hover-tooltip-time {
  font-weight: 600;
  margin-bottom: 4px;
  white-space: nowrap;
}
.hover-tooltip-nocoverage {
  font-size: 11px;
  opacity: 0.6;
  font-style: italic;
  margin-bottom: 4px;
}
.hover-tooltip-row {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 1px 0;
}
.hover-tooltip-band {
  flex: 1 1 auto;
  opacity: 0.85;
  margin-right: 10px;
}
.hover-tooltip-count {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}
.hover-tooltip-empty {
  opacity: 0.6;
  font-style: italic;
}
.x-axis {
  grid-column: 2;
  grid-row: 2;
  position: relative;
}
.hour-mark {
  position: absolute;
  top: 0;
  transform: translateX(-50%);
  font-size: 9px;
  opacity: 0.45;
  white-space: nowrap;
}
.hour-mark.align-start {
  transform: none;
}
.hour-mark.align-end {
  transform: translateX(-100%);
}

// Empty state: no working Vega connection yet
.onboarding {
  display: flex;
  flex-direction: column;
  gap: 20px;
}
.onboarding-banner {
  position: relative;
  padding: 16px 18px;
  border: 1px solid rgba(79, 195, 247, 0.35);
  border-radius: 8px;
  background: rgba(79, 195, 247, 0.06);
}
.onboarding-title {
  font-size: 16px;
  font-weight: 600;
  margin-bottom: 4px;
  padding-right: 36px; // clear the corner refresh button
}
.onboarding-body {
  font-size: 13px;
  opacity: 0.8;
  line-height: 1.5;
  max-width: 640px;
}
.onboarding-body code {
  font-size: 12px;
  padding: 1px 4px;
  border-radius: 3px;
  background: rgba(128, 128, 128, 0.2);
}
// CTAs stack under the copy: primary button, then secondary text link
// Primary + ghost CTA side by side under the copy
.onboarding-actions {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
  margin-top: 14px;
}
.onboarding-cta {
  padding: 8px 18px;
  border-radius: 999px;
  background: #4fc3f7;
  color: #0a1a22;
  font-size: 13px;
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
}
.onboarding-cta-ghost {
  padding: 8px 18px;
  border-radius: 999px;
  background: transparent;
  border: 1px solid rgba(79, 195, 247, 0.6);
  color: #4fc3f7;
  font-size: 13px;
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
  transition: background 0.15s;
}
.onboarding-cta-ghost:hover {
  background: rgba(79, 195, 247, 0.12);
}
.onboarding-steps {
  margin: 12px 0 0;
  padding-left: 22px;
  font-size: 13px;
  line-height: 1.6;
  opacity: 0.85;
  max-width: 640px;
}
.onboarding-steps code {
  font-size: 12px;
  padding: 1px 4px;
  border-radius: 3px;
  background: rgba(128, 128, 128, 0.2);
}
.onboarding-error {
  margin-top: 8px;
  font-size: 12px;
  color: #e57373;
}
// Refresh lives in the banner's top-right corner
.onboarding-refresh {
  position: absolute;
  top: 10px;
  right: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: none;
  border: none;
  color: inherit;
  opacity: 0.6;
  cursor: pointer;
  transition: opacity 0.15s;
}
.onboarding-refresh:hover:not(:disabled) {
  opacity: 1;
  background: rgba(128, 128, 128, 0.15);
}
.onboarding-refresh:disabled {
  cursor: default;
  opacity: 0.4;
}
.onboarding-refresh.spinning :deep(.v-icon) {
  animation: onboarding-spin 0.9s linear infinite;
}
@keyframes onboarding-spin {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}
</style>
