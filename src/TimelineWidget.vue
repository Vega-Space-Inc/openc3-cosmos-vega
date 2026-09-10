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
  <!-- resize: both gives the widget a drag grip in its bottom-right corner.
       The COSMOS screen card sizes to its content, so dragging the grip
       resizes the whole window; the chosen size is kept per browser and
       double-clicking the grip corner puts it back to automatic. -->
  <div
    ref="root"
    class="timeline-widget"
    :style="[
      computedStyle,
      userSizeStyle,
      { '--label-w': labelWidthPx + 'px' },
    ]"
    @mousedown="onRootMouseDown"
    @dblclick="onRootDblClick"
  >
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
          <div class="ctl-wrap" :class="{ busy }">
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
            <div v-if="busy" class="ctl-shimmer" />
          </div>
          <!-- Multi-select: each selected station adds a row to every band -->
          <div class="ctl-wrap" :class="{ busy }">
            <v-select
              v-model="selectedGroundStationIds"
              :items="groundStationOptions"
              item-title="label"
              item-value="id"
              multiple
              density="compact"
              hide-details
              variant="outlined"
              style="max-width: 360px"
              :disabled="loading || workspaceLoading"
            >
              <!-- Two chips, then '+N': the field stays one line high -->
              <template #selection="{ item, index }">
                <v-chip
                  v-if="index < 2"
                  size="small"
                  closable
                  @click:close.stop="removeStation(item.value)"
                >
                  {{ item.title }}
                </v-chip>
                <span v-else-if="index === 2" class="more-selected"
                  >+{{ selectedGroundStationIds.length - 2 }}</span
                >
              </template>
            </v-select>
            <div v-if="busy" class="ctl-shimmer" />
          </div>
          <!-- Bands: all on by default; deselect to hide a band's rows -->
          <div class="ctl-wrap" :class="{ busy }">
            <v-select
              v-model="selectedBands"
              :items="bandOptions"
              item-title="label"
              item-value="id"
              multiple
              density="compact"
              hide-details
              variant="outlined"
              style="max-width: 300px"
              :disabled="loading || workspaceLoading"
            >
              <template #selection="{ item, index }">
                <span v-if="allBandsSelected && index === 0" class="sel-text"
                  >All bands</span
                >
                <template v-else-if="!allBandsSelected">
                  <v-chip
                    v-if="index < 3"
                    size="small"
                    closable
                    @click:close.stop="toggleBandOff(item.value)"
                  >
                    {{ item.title }}
                  </v-chip>
                  <span v-else-if="index === 3" class="more-selected"
                    >+{{ selectedBands.length - 3 }}</span
                  >
                </template>
              </template>
            </v-select>
            <div v-if="busy" class="ctl-shimmer" />
          </div>
          <!-- Refresh + settings sit on the row's right edge -->
          <v-btn
            class="ml-auto"
            color="primary"
            variant="flat"
            style="height: 32px"
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
          <v-menu :close-on-content-click="false">
            <template #activator="{ props }">
              <v-btn
                icon
                variant="text"
                style="height: 32px; width: 32px"
                v-bind="props"
              >
                <v-icon>mdi-cog</v-icon>
              </v-btn>
            </template>
            <v-list density="compact">
              <!-- Organization switch: an internal (Vega) affordance, so it
                   only appears when COSMOS is running locally -->
              <template v-if="showOrgPicker">
                <v-list-item>
                  <v-select
                    v-model="selectedOrgId"
                    :items="orgOptions"
                    item-title="label"
                    item-value="id"
                    label="Organization"
                    density="compact"
                    hide-details
                    variant="outlined"
                    style="min-width: 240px"
                    :disabled="loading || workspaceLoading"
                  />
                </v-list-item>
                <v-divider />
              </template>
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
              <v-divider />
              <v-list-item>
                <v-switch
                  v-model="use24h"
                  label="24-hour time"
                  density="compact"
                  hide-details
                  color="secondary"
                />
              </v-list-item>
              <v-list-item disabled density="compact">
                <v-list-item-title class="build-stamp"
                  >Widget build {{ BUILD_STAMP }}</v-list-item-title
                >
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
        <div class="ctl-wrap" :class="{ busy }">
          <v-btn-toggle v-model="quickDay" variant="text" class="quick-days">
            <v-btn :value="-1" :disabled="loading">Yesterday</v-btn>
            <v-btn :value="0" :disabled="loading">Today</v-btn>
            <v-btn :value="1" :disabled="loading">Tomorrow</v-btn>
          </v-btn-toggle>
          <div v-if="busy" class="ctl-shimmer" />
        </div>
        <!-- Calendar: a compact icon button opening a short list - the last
             four days and the next three - with today and the selected day
             marked and days past the forecast horizon greyed out. -->
        <div class="ctl-wrap" :class="{ busy }">
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
                  <span class="day-kind" :class="d.kind">{{
                    d.kindLabel
                  }}</span>
                </template>
              </v-list-item>
            </v-list>
          </v-menu>
          <div v-if="busy" class="ctl-shimmer" />
        </div>
        <div class="window-nav-right">
          <v-btn
            v-if="historyNeeded"
            variant="outlined"
            style="height: 32px"
            :loading="historyLoading"
            :disabled="loading"
            title="The earlier part of this day is before the current forecast run. Vega's measured-history build takes 30-45 seconds."
            @click="loadHistoryNow"
          >
            Load measured history
          </v-btn>
          <!-- Errors only: the shimmer rows already say "loading". The box
               can shrink (min-width 0, ellipsis) so a long message never
               widens the widget or adds a line. -->
          <span
            v-if="errorText && !loading"
            class="status-text error-text"
            :title="errorText"
          >
            {{ errorText }}
          </span>
          <button
            v-if="zoomRange"
            type="button"
            class="quiet-link bordered"
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
        <div class="lanes-body" @mouseleave="hoverBand = null">
          <!-- With several stations, a faint band behind each band's group
               of rows (labels and plot alike) shows which rows belong
               together; the wider gap between groups stays untinted. -->
          <div
            v-for="g in multiStation ? bandGroups : []"
            :key="'group-' + g.band"
            class="band-group-bg"
            :style="{
              top: g.top + 'px',
              height: g.height + 'px',
              background: bandTint(g.band, 0.09),
            }"
          />
          <div class="lanes-labels" :style="{ height: gridHeightPx + 'px' }">
            <!-- Band header: one bordered, tinted block per band spanning
                 that band's rows (one row per selected station) -->
            <div
              v-for="g in bandGroups"
              :key="'band-' + g.band"
              class="band-block"
              :class="{ hovered: hoverBand && rowBand(hoverBand) === g.band }"
              :style="{
                top: g.rowTop + 'px',
                height: g.rowHeight + 'px',
                background: bandTint(
                  g.band,
                  hoverBand && rowBand(hoverBand) === g.band ? 0.4 : 0.24,
                ),
                color: bandColor(g.band),
              }"
            >
              {{ g.band }}
            </div>
            <!-- Per row: the station name, right against its track -->
            <div
              v-for="band in rowKeys"
              :key="'label-' + band"
              class="lane-label"
              :style="rowGeometry[band]"
              :class="{
                expanded: expandedBand === band,
                hovered: hoverBand === band,
              }"
              @mouseenter="hoverBand = band"
              @click="onLaneClick(band)"
            >
              <span v-if="multiStation" class="lane-sub">{{
                stationNames[rowGs(band)] || rowGs(band)
              }}</span>
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
            <!-- While a load is in flight the rows shimmer and nothing else
                 is drawn: the chart appears whole when every station and
                 day has landed, instead of re-flowing as each one does. -->
            <template v-if="loading">
              <div
                v-for="key in rowKeys"
                :key="'skel-' + key"
                class="skeleton-row"
                :style="rowGeometry[key]"
              />
            </template>
            <div v-if="!loading" class="lanes-stack">
              <div
                v-for="band in rowKeys"
                :key="'lane-' + band"
                class="lane-plot"
                :style="{
                  height: rowHeightPx(band) + 'px',
                  marginBottom: rowGap(band) + 'px',
                }"
                :class="{
                  expanded: expandedBand === band,
                  hovered: hoverBand === band,
                }"
                @mouseenter="hoverBand = band"
                @click="onCellClick(band, $event)"
              >
                <svg
                  class="lane-svg"
                  :viewBox="`${viewStart} ${-CHART_H * LANE_HEADROOM} ${viewEnd - viewStart} ${CHART_H * (1 + LANE_HEADROOM)}`"
                  preserveAspectRatio="none"
                >
                  <!-- One path per ramp step, each a run of narrow rects
                     rising from the baseline with a gap between neighbours.
                     The viewBox does the horizontal scaling on zoom. -->
                  <!-- Hovered cell's backdrop, beneath the bars -->
                  <rect
                    v-if="hoverSpan && hoverSpan.key === band"
                    v-bind="svgRect(hoverSpan, band)"
                    fill="rgba(255, 255, 255, 0.08)"
                  />
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
                        :fill="BAR_COLORS[step]"
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
                        :fill="BAR_COLORS[step]"
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
                  <!-- One outline per covered span: the box hugs the minutes
                       this station has in the pass. Drawn here rather than
                       as an HTML overlay so it shares the bars' geometry. -->
                  <template v-if="!emptyBands[rowBand(band)]">
                    <rect
                      v-for="span in rowSpans[band] || []"
                      :key="'outline-' + span.id"
                      v-bind="svgRect(span, band)"
                      fill="none"
                      :stroke="
                        hoverSpan && hoverSpan.id === span.id
                          ? 'rgba(255, 255, 255, 0.75)'
                          : 'rgba(128, 128, 128, 0.35)'
                      "
                      stroke-width="1"
                      vector-effect="non-scaling-stroke"
                    />
                  </template>
                </svg>
              </div>
            </div>
            <!-- One outlined box per (row, contiguous covered span). The
                 box hugs the minutes that station actually has in the
                 pass, so with several stations the empty space falls
                 BETWEEN boxes rather than inside them; a station that
                 doesn't see a pass has no box there at all. -->
            <template v-if="!loading">
              <div
                v-for="span in allSpans"
                :key="span.id"
                class="pass-cell"
                :style="spanStyle(span)"
                :class="{
                  expanded: expandedBand === span.key,
                  placeholder: emptyBands[rowBand(span.key)],
                  active:
                    !emptyBands[rowBand(span.key)] &&
                    hoverCell &&
                    hoverCell.spanId === span.id,
                }"
              >
                <span
                  v-if="
                    !emptyBands[rowBand(span.key)] &&
                    cellStatus[span.id] !== 'data' &&
                    spanWidthPx(span) >= 58
                  "
                  class="cell-note"
                  :class="cellStatus[span.id]"
                >
                  {{
                    cellStatus[span.id] === 'clear'
                      ? 'Clear'
                      : cellStatus[span.id] === 'loading'
                        ? 'Loading…'
                        : 'No data'
                  }}
                </span>
              </div>
              <!-- A band with nothing in the whole window gets one cell across
                 all the passes saying so, instead of a row of empty boxes. -->
              <div
                v-for="band in rowKeys.filter((k) => emptyBands[rowBand(k)])"
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
            </template>
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
                <span class="hover-tooltip-band">{{ row.label }}</span>
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

        <div class="x-axis-row" :class="{ 'two-line': axisTwoLine }">
          <div class="x-axis-spacer" />
          <div class="x-axis">
            <span
              v-for="mark in loading ? [] : axisMarks"
              :key="'mark-' + (mark.align || 'c') + mark.c"
              class="hour-mark"
              :class="'align-' + (mark.align || 'center')"
              :style="{ left: cToPct(mark.c) + '%' }"
            >
              <div v-for="(line, i) in mark.lines" :key="i">{{ line }}</div>
            </span>
            <!-- Small tick in each gap between passes, separating one
                 pass's start/end times from the next's -->
            <span
              v-for="seg in segments.slice(1)"
              :key="'axis-sep-' + seg.cstart"
              class="axis-divider"
              :style="{ left: cToPct(seg.cstart - passGapUnits / 2) + '%' }"
            />
          </div>
        </div>
        <div v-if="emptyBandCount" class="empty-bands-row">
          <div class="x-axis-spacer" />
          <button
            type="button"
            class="quiet-link"
            @click="showEmptyBands = !showEmptyBands"
          >
            {{ showEmptyBands ? 'Hide' : 'Show' }} {{ emptyBandCount }}
            {{ emptyBandCount === 1 ? 'band' : 'bands' }} with no data
          </button>
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
            <span class="asi-info-label">ASI Risk Overview</span>
          </button>
        </div>

        <v-dialog v-model="showAsiInfo" max-width="600" scrollable>
          <v-card class="asi-info">
            <v-card-title class="asi-info-title"
              >ASI Risk Overview</v-card-title
            >
            <v-card-text class="asi-info-body">
              <p>
                <strong>Adjacent satellite interference (ASI)</strong> is the
                risk that another satellite transmitting in the same frequency
                band is in your ground station's view at the same time as the
                satellite you are tracking, so its signal can land in your
                receiver alongside the one you want.
              </p>
              <h4>How Vega calculates it</h4>
              <ol>
                <li>
                  <strong>Visibility.</strong> Vega propagates the orbit of the
                  selected satellite and works out, minute by minute, when it is
                  above the horizon from the selected ground station. Those
                  minutes are the passes you see as boxes; a satellite that is
                  always in view (GEO) gives one box for the whole day.
                </li>
                <li>
                  <strong>Candidates.</strong> From the catalog of tracked
                  satellites it selects the ones whose transmit frequencies
                  overlap a band the selected satellite uses. Satellites in
                  other bands are ignored.
                </li>
                <li>
                  <strong>Overlap.</strong> For every covered minute and every
                  band, it counts how many of those candidates are
                  simultaneously in view of the station. That count is the
                  <strong>interferer count</strong> - the number behind each
                  bar.
                </li>
              </ol>
              <h4>Reading the chart</h4>
              <ul>
                <li>
                  Each bar is one minute (or a few minutes when the view is too
                  narrow to show them individually - the tooltip then says
                  which). Its height and colour are that minute's interferer
                  count relative to the band's busiest minute in the loaded day,
                  from green (quiet) through amber to red (the peak). The
                  tooltip gives the actual count.
                </li>
                <li>
                  Vega's own severity scale is absolute: a minute with 1 or more
                  interferers is a <em>warning</em> and 10 or more is
                  <em>high</em>. The COSMOS limits on the
                  <code>FORECASTING_SUMMARY</code> packet use that scale.
                </li>
                <li>
                  Today and the next two days come from the latest forecast run
                  (refreshed several times a day); earlier days are the measured
                  record for that day. The chart only shows time when the
                  satellite is in view - gaps between passes are removed.
                </li>
              </ul>
              <p class="asi-info-note">
                Counts are geometric and spectral - they say how many same-band
                satellites share the station's sky, not the received power of
                each. Treat a high count as a cue to check the pass, not as a
                measured carrier-to-interference ratio.
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
const PASS_GAP_PX = 5
// Vertical gap between band rows - the same size as the gap between
// passes, so the chart reads as a grid of (pass x band) cells.
const LANE_GAP_PX = 5
// Context minutes on each side of a pass. Zero: slices (unlike the old
// lines) don't need to rise from a baseline, and any padding is dead space
// inside the box.
const PASS_PAD_MIN = 0

// Today/forecast day responses go stale (the forecast refreshes, and
// today's measured portion keeps growing); past days never do.
const FORECAST_CACHE_TTL_MS = 5 * 60_000
// Persisted history slices (localStorage): key prefix and how many to keep.
// A day slice is ~130 KB, so 24 entries stays well inside the usual quota.
const HISTORY_LS_PREFIX = 'vega_widget_history:'
const HISTORY_LS_MAX_ENTRIES = 24
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
// History points once keyed counts by the raw FrequencyBand name
// ("S-band"); day_detail and current history use the chart label ("S").
// Accept both.
function normalizeBandKeys(counts) {
  const out = {}
  for (const [k, v] of Object.entries(counts)) {
    let label = String(k)
      .replace(/[-_ ]?band$/i, '')
      .replace(/_/g, ' ')
      .toUpperCase()
    label = { KU: 'Ku', KA: 'Ka', MMWAVE: 'mmWave' }[label] || label
    out[label] = v
  }
  return out
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
// A clear minute (analysed, nothing there) still gets a bar: a stub a
// couple of pixels tall in a muted green, so the minute is there to hover
// and the row reads as "observed and clear" rather than "nothing here".
const CLEAR_STUB_COLOR = 'rgba(67, 160, 71, 0.55)'
const CLEAR_STUB_H = 0.05 // of CHART_H
const CLEAR_STEP = RAMP_STEPS // index of the stub path in a row's path list
const BAR_COLORS = [...RAMP_COLORS, CLEAR_STUB_COLOR]
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
// Fire-and-forget: the command API normally blocks until the interface
// acks the write, and the interface only acks AFTER Vega has answered the
// HTTP request. A slow endpoint (history takes 30-45s) therefore blew the
// API's 30s ack wait, returned a 500, and got re-sent - each re-send queued
// behind the first inside the interface until nothing else could get
// through. The widget already confirms delivery by watching the packet
// land in the CVT, so it has no use for the ack at all.
const CMD_KWARGS = { timeout: 0 }
// Should an ack wait still happen (older COSMOS ignoring timeout: 0), its
// expiry is not a failure: the request is still in flight.
function isAckTimeout(e) {
  const msg = e?.response?.data?.error?.message || e?.message || ''
  return /waiting for cmd ack/i.test(msg)
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
const SIZE_LS_KEY = 'vega_widget_size'
const TIME_24H_LS_KEY = 'vega_widget_24h'
function readStoredFlag(key, fallback) {
  try {
    const raw = localStorage.getItem(key)
    return raw === null ? fallback : raw === '1'
  } catch (e) {
    return fallback
  }
}
function readStoredSize() {
  try {
    const raw = localStorage.getItem(SIZE_LS_KEY)
    if (!raw) return null
    const { w } = JSON.parse(raw)
    return Number.isFinite(w) && w > 0 ? { w } : null
  } catch (e) {
    return null
  }
}
// Width of the bottom-right corner that counts as the resize grip.
const GRIP_PX = 20
// Identity colour per band - for the band block and the tinted strip
// behind its rows, never for the bars (those keep the severity ramp).
// Hues stay clear of the ramp's green / amber / red.
const BAND_COLORS = {
  VHF: '#7e57c2',
  UHF: '#42a5f5',
  L: '#26a69a',
  S: '#ec407a',
  C: '#5c6bc0',
  X: '#29b6f6',
  Ku: '#ab47bc',
  Ka: '#78909c',
  mmWave: '#8d6e63',
}
function bandColor(band) {
  if (BAND_COLORS[band]) return BAND_COLORS[band]
  // Unknown band: a stable hue from its name
  let h = 0
  for (const ch of String(band)) h = (h * 31 + ch.charCodeAt(0)) % 360
  return `hsl(${h}, 55%, 60%)`
}
function bandTint(band, alpha) {
  const c = bandColor(band)
  if (c.startsWith('#')) {
    const r = parseInt(c.slice(1, 3), 16)
    const g = parseInt(c.slice(3, 5), 16)
    const b = parseInt(c.slice(5, 7), 16)
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }
  return c.replace('hsl(', 'hsla(').replace(')', `, ${alpha})`)
}
// With several ground stations selected every band gets one row per
// station; rows of one band sit LANE_GAP_PX apart and bands GROUP_GAP_PX.
// Bands are far enough apart that, with each band's strip padded 8px above
// and below its rows, 8px of plain background still shows between strips.
const GROUP_GAP_PX = 24
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
      BUILD_STAMP:
        typeof __VEGA_WIDGET_BUILD__ === 'string'
          ? __VEGA_WIDGET_BUILD__
          : 'dev',
      BAR_COLORS,
      // COSMOS 'time_zone' setting - see the Time zone block up top.
      timeZone: 'local',
      // 24-hour (default) or 12-hour clock for every time label; remembered
      // per browser.
      use24h: readStoredFlag(TIME_24H_LS_KEY, true),
      // Wall clock, ticked every 30s so the "now" line moves.
      nowMs: Date.now(),
      showAsiInfo: false,
      // Rows for bands with nothing in the loaded window are hidden until
      // the user asks for them.
      showEmptyBands: false,
      // Size the user dragged the widget to ({w, h} in CSS px), or null for
      // automatic. Remembered in this browser.
      userSize: readStoredSize(),
      // Height of the lanes area, kept current by the ResizeObserver; with
      // a user-set height the band rows share it (see rowHeights).
      laneAreaPx: 0,
      // Measured history the current window could still fetch on request
      // ({pastDays, range}), and whether that fetch is running.
      pendingHistory: null,
      historyLoading: false,
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
      selectedGroundStationIds: [],
      // stationDayData[gsId][date] = { minutes: [...], toneWarningMin, toneHighMin }
      stationDayData: {},
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
    // The first selected station - what the single-station paths (measured
    // history, the Refresh guard) act on.
    selectedGroundStationId() {
      return this.selectedGroundStationIds.length
        ? this.selectedGroundStationIds[0]
        : null
    },
    selectedGroundStation() {
      return (
        this.groundStations.find(
          (gs) => gs.id === this.selectedGroundStationId,
        ) || null
      )
    },
    // Selected stations in the order they were picked.
    selectedStations() {
      return this.selectedGroundStationIds
        .map((id) => this.groundStations.find((gs) => gs.id === id))
        .filter(Boolean)
    },
    busy() {
      return this.loading || this.workspaceLoading
    },
    // The organization switch is for Vega's own use (customers have one
    // org): shown only when COSMOS itself is running on this machine.
    showOrgPicker() {
      if (this.organizations.length < 2) return false
      const host = (window.location && window.location.hostname) || ''
      return (
        host === 'localhost' ||
        host === '127.0.0.1' ||
        host === '::1' ||
        host.endsWith('.local')
      )
    },
    bandOptions() {
      return this.bands.map((b) => ({ id: b, label: b }))
    },
    // The band picker is a view over visibleBands (all on by default).
    selectedBands: {
      get() {
        return this.bands.filter((b) => this.visibleBands[b])
      },
      set(list) {
        const v = {}
        for (const b of this.bands) v[b] = list.includes(b)
        this.visibleBands = v
        if (this.expandedBand && !v[this.rowBand(this.expandedBand)]) {
          this.expandedBand = null
        }
      },
    },
    allBandsSelected() {
      return (
        this.bands.length > 0 && this.selectedBands.length === this.bands.length
      )
    },
    multiStation() {
      return this.selectedStations.length > 1
    },
    stationNames() {
      const result = {}
      for (const gs of this.groundStations) result[String(gs.id)] = gs.name
      return result
    },
    // Grid rows: for every visible band, one row per selected station,
    // keyed '<band>|<gsId>' (see rowBand / rowGs).
    rowKeys() {
      const keys = []
      for (const band of this.visibleBandList) {
        for (const gs of this.selectedStations) keys.push(`${band}|${gs.id}`)
      }
      return keys
    },
    // Each selected station's minutes on the window's grid.
    stationEntries() {
      const result = {}
      for (const gs of this.selectedStations) {
        const data = this.stationDayData[gs.id]
        result[String(gs.id)] = data ? this.entriesFrom(data) : null
      }
      return result
    },
    bands() {
      return (this.selectedSatellite && this.selectedSatellite.bands) || []
    },
    // Bands currently shown as lanes (the legend chips toggle these).
    // Bands with data first (in the satellite's own order); the ones with
    // nothing in the loaded window are hidden behind the 'show bands with
    // no data' control and, when shown, sit at the bottom.
    visibleBandList() {
      const visible = this.bands.filter((b) => this.visibleBands[b])
      const empty = this.emptyBands
      const withData = visible.filter((b) => !empty[b])
      if (!this.showEmptyBands) return withData
      return [...withData, ...visible.filter((b) => empty[b])]
    },
    // True while part of the window precedes what the forecast run covers
    // and no measured history has been loaded for it - i.e. the 'Load
    // measured history' button would add something.
    historyNeeded() {
      const pending = this.pendingHistory
      if (!pending || !this.hasLoadedData) return false
      const start = this.day0StartMs
      const from = Math.max(
        0,
        Math.round((new Date(pending.range.startIso) - start) / 60000),
      )
      const to = Math.min(
        this.totalMinutes,
        Math.round((new Date(pending.range.endIso) - start) / 60000),
      )
      const entries = this.minuteEntries
      for (let i = from; i < to; i++) {
        if (entries[i] && entries[i].covered) return false
      }
      return to > from
    },
    emptyBandCount() {
      return this.bands.filter(
        (b) => this.visibleBands[b] && this.emptyBands[b],
      ).length
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
          // Only 'today' and the horizon get a tag; past/forecast is
          // obvious from the position relative to today.
          kindLabel: disabled
            ? 'no forecast yet'
            : kind === 'today'
              ? 'today'
              : '',
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
    // The window's minutes as the UNION of coverage across the selected
    // stations (covered when any of them sees the satellite). This is what
    // the shared pass axis compresses on, so with a LEO the passes of every
    // selected station line up in one set of boxes; a station that doesn't
    // see a pass is simply empty there. Counts live per station in
    // stationEntries. With one station this is that station's own minutes.
    minuteEntries() {
      const stations = Object.values(this.stationEntries).filter(Boolean)
      if (stations.length === 1) return stations[0]
      const map = new Array(this.totalMinutes).fill(null)
      const start = this.day0StartMs
      for (const entries of stations) {
        entries.forEach((entry, idx) => {
          if (!entry) return
          if (!map[idx]) {
            map[idx] = {
              timestamp: new Date(start + idx * 60000).toISOString(),
              covered: false,
              counts: {},
            }
          }
          if (entry.covered) map[idx].covered = true
        })
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
      const vStart = this.viewStart
      const vEnd = this.viewEnd
      const span = Math.max(1, vEnd - vStart)
      const px = this.laneWidthPx || 1200
      // Clock ticks whenever the view lies within ONE pass: a GEO's
      // day-long coverage, a GEO whose coverage only starts partway through
      // the day (the earlier part is before the forecast run), or any pass
      // the user has zoomed into. Otherwise each pass gets its edge times.
      const only = segs.find(
        (s) => vStart >= s.cstart - 1e-6 && vEnd <= s.cstart + s.clen + 1e-6,
      )
      if (only) {
        const seg = only
        // About a dozen ticks across the view, never closer than ~70px.
        const rough = Math.max(span / 12, (span * (this.use24h ? 70 : 90)) / px)
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
        const toIdx = (c) => seg.startIdx + (c - seg.cstart)
        const labelAt = (idx) => {
          const hm = this.formatHM(this.idxToDate(idx))
          return idx === seg.endIdx && hm === '00:00' ? '24:00' : hm
        }
        const marks = [
          { c: vStart, lines: [labelAt(toIdx(vStart))], align: 'start' },
        ]
        const first = Math.ceil(toIdx(vStart) / interval) * interval
        for (let idx = first; idx < toIdx(vEnd); idx += interval) {
          const c = seg.cstart + (idx - seg.startIdx)
          if (c - vStart < interval / 4 || vEnd - c < interval / 4) continue
          marks.push({ c, lines: [labelAt(idx)] })
        }
        marks.push({ c: vEnd, lines: [labelAt(toIdx(vEnd))], align: 'end' })
        return marks
      }
      // Several passes: one label per pass, centred under its box, showing
      // as much as fits - the full range on one line, the range stacked on
      // two lines, the start time alone, or nothing (the tooltip still has
      // it). Labels are then placed left to right and any that would run
      // into the previous one is shrunk until it fits, or dropped.
      const pxPerUnit = px / span
      const charPx = this.use24h ? 7 : 6.6
      const width = (text) => text.length * charPx
      const marks = []
      let lastRight = -Infinity
      for (const s of segs) {
        const boxPx = s.clen * pxPerUnit
        const cx = s.cstart + s.clen / 2
        const cpx = (cx - vStart) * pxPerUnit
        const options = [
          { lines: [`${s.startLabel} – ${s.endLabel}`] },
          { lines: [s.startLabel, s.endLabel] },
          { lines: [s.startLabel] },
        ]
        let placed = null
        for (const opt of options) {
          const w = Math.max(...opt.lines.map(width))
          // must fit its own box (plus a little air) and clear the last label
          if (w > boxPx + 10) continue
          if (cpx - w / 2 < lastRight + 8) continue
          placed = { c: cx, lines: opt.lines, align: 'center', w }
          break
        }
        if (placed) {
          marks.push(placed)
          lastRight = cpx + placed.w / 2
        }
      }
      return marks
    },
    // Each lane is scaled to ITS OWN band's peak, not a shared maximum -
    // severity is relative to the band (5 interferers on VHF can matter more
    // than 55 on S), and a shared scale would flatten quiet bands into
    // near-identical baselines. The expanded lane's tick values come from
    // the same per-band max, so the numbers stay honest.
    bandMaxes() {
      const result = {}
      for (const band of this.bands) {
        // One scale per band across the selected stations, so their rows
        // compare honestly.
        let max = 0
        for (const entries of Object.values(this.stationEntries)) {
          if (!entries) continue
          for (const entry of entries) {
            const c = this.countOf(entry, band)
            if (c !== null && c > max) max = c
          }
        }
        result[band] = this.niceMax(max)
      }
      return result
    },
    // Y-tick values for the click-expanded lane, on that band's own scale.
    expandedYTicks() {
      if (!this.expandedBand) return []
      const max = this.bandMaxes[this.rowBand(this.expandedBand)] || 1
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
      for (const key of this.rowKeys) {
        // A band judged 'no data' draws nothing - a row of clear stubs
        // would read as "observed and clear", which it is not.
        result[key] = this.emptyBands[this.rowBand(key)]
          ? []
          : this.buildBandBars(key)
      }
      return result
    },
    rampCss() {
      return `linear-gradient(90deg, ${RAMP_COLORS.join(', ')})`
    },
    // Room for band + station names when several stations are selected.
    // Room for the band block, plus station names with several stations,
    // plus the count ticks while a row is open (single-station view has no
    // station column for them to share).
    labelWidthPx() {
      if (this.multiStation) return 176
      return this.expandedBand ? 96 : 52
    },
    userSizeStyle() {
      if (!this.userSize) return {}
      return { width: `${this.userSize.w}px` }
    },
    // Band row height in px. Automatic: 46 (220 expanded). With a user-set
    // height the rows share the lanes area: all rows grow equally up to
    // COLLAPSED_MAX_PX (a tall widget keeps compact sparklines rather than
    // three screen-filling rows; clicking a band is how to see it large),
    // or, with a band expanded, the others stay at 46 and the expanded one
    // takes the rest. Never below the automatic sizes, so a short window
    // scrolls rather than squashing the bars.
    // Band row height in px: 36 (24 with several stations), 200 expanded.
    // Fixed - a taller widget adds room below the grid, never taller rows.
    rowHeights() {
      const base = this.multiStation ? 24 : 36
      const result = {}
      for (const b of this.rowKeys) {
        result[b] = this.expandedBand === b ? 200 : base
      }
      return result
    },
    axisTwoLine() {
      return this.axisMarks.some((m) => m.lines && m.lines.length > 1)
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
      for (const key of this.rowKeys) {
        result[key] = this.buildBandBars(key, range)
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
      for (const b of this.rowKeys) {
        const h = this.rowHeights[b]
        result[b] = { top: `${top}px`, height: `${h}px` }
        top += h + this.rowGap(b)
      }
      return result
    },
    // Whether the loaded data carries the null-vs-0 contract at all. Vega
    // builds before feat/frontend-counts-nil-when-unanalyzed sent 0 for a
    // band the run never aggregated, so their all-zero bands can't be
    // told from clear ones; until a response contains a null somewhere,
    // an all-zero band is treated as 'no reading' (the old behaviour).
    // Remove once that API change is deployed everywhere.
    countsCarryNulls() {
      for (const entries of Object.values(this.stationEntries)) {
        if (!entries) continue
        for (const entry of entries) {
          if (!entry || !entry.covered || !entry.counts) continue
          for (const v of Object.values(entry.counts)) {
            if (v === null) return true
          }
        }
      }
      return false
    },
    // Bands with no reading anywhere in the loaded window (every covered
    // minute null). A band that was analysed and found clear all day is NOT
    // empty - it keeps its row, with its cells marked clear.
    emptyBands() {
      const result = {}
      // No verdicts mid-load: a band that simply hasn't arrived yet would
      // otherwise be hidden as empty and pop back in when it lands.
      if (!this.hasLoadedData || this.loading) return result
      const legacy = !this.countsCarryNulls
      for (const band of this.bands) {
        let any = false
        for (const entries of Object.values(this.stationEntries)) {
          if (!entries) continue
          for (const entry of entries) {
            const c = this.countOf(entry, band)
            if (c === null) continue
            if (!legacy || c > 0) {
              any = true
              break
            }
          }
          if (any) break
        }
        result[band] = !any
      }
      return result
    },
    // Per (pass, band) cell: 'data' (something to draw), 'clear' (readings,
    // all zero) or 'nodata' (no reading in the pass).
    // Per row, the contiguous covered spans inside each pass segment, in
    // compressed coordinates: { [rowKey]: [{ id, key, cstart, clen,
    // startIdx, endIdx }] }. A row whose station hasn't loaded yet gets the
    // whole segment (so a 'Loading' box shows). With one station selected
    // every segment is one span - the box is the pass, as before.
    rowSpans() {
      const result = {}
      for (const key of this.rowKeys) {
        const entries = this.rowEntries(key)
        const spans = []
        for (const seg of this.segments) {
          if (!entries) {
            spans.push({
              id: `${key}|${seg.startIdx}`,
              key,
              cstart: seg.cstart,
              clen: seg.clen,
              startIdx: seg.startIdx,
              endIdx: seg.endIdx,
              loading: true,
            })
            continue
          }
          let runStart = null
          for (let i = seg.startIdx; i <= seg.endIdx; i++) {
            const covered =
              i < seg.endIdx && !!(entries[i] && entries[i].covered)
            if (covered && runStart === null) runStart = i
            if (!covered && runStart !== null) {
              spans.push({
                id: `${key}|${runStart}`,
                key,
                cstart: seg.cstart + (runStart - seg.startIdx),
                clen: i - runStart,
                startIdx: runStart,
                endIdx: i,
              })
              runStart = null
            }
          }
        }
        result[key] = spans
      }
      return result
    },
    // Vertical extent of each band's group of rows (multi-station only).
    bandGroups() {
      const groups = []
      let current = null
      for (const key of this.rowKeys) {
        const band = this.rowBand(key)
        const geo = this.rowGeometry[key]
        if (!geo) continue
        const top = parseFloat(geo.top)
        const bottom = top + parseFloat(geo.height)
        if (!current || current.band !== band) {
          current = { band, top, bottom }
          groups.push(current)
        } else {
          current.bottom = bottom
        }
      }
      const pad = 8
      return groups.map((g) => ({
        band: g.band,
        // the tinted strip (padded) and the exact rows extent (band block)
        top: g.top - pad,
        height: g.bottom - g.top + pad * 2,
        rowTop: g.top,
        rowHeight: g.bottom - g.top,
      }))
    },
    // Total height of the rows, for the absolutely-positioned label column.
    gridHeightPx() {
      const keys = this.rowKeys
      if (!keys.length) return 0
      const last = this.rowGeometry[keys[keys.length - 1]]
      return last ? parseFloat(last.top) + parseFloat(last.height) : 0
    },
    allSpans() {
      return this.rowKeys.flatMap((key) => this.rowSpans[key] || [])
    },
    // 'data' | 'clear' | 'nodata' | 'loading' per span.
    cellStatus() {
      const result = {}
      for (const span of this.allSpans) {
        if (span.loading) {
          result[span.id] = 'loading'
          continue
        }
        const entries = this.rowEntries(span.key)
        const band = this.rowBand(span.key)
        let seen = false
        let any = false
        for (let i = span.startIdx; i < span.endIdx; i++) {
          const c = this.countOf(entries[i], band)
          if (c === null) continue
          seen = true
          if (c > 0) {
            any = true
            break
          }
        }
        result[span.id] = any ? 'data' : seen ? 'clear' : 'nodata'
      }
      return result
    },
    // The hovered grid cell (pass x band): which one, and where its backdrop
    // goes.
    hoverCell() {
      const slot = this.hoverSlot
      const band = this.hoverBand
      if (!slot || !band) return null
      if (this.emptyBands[this.rowBand(band)]) return null
      const span = this.spanAt(band, slot.start)
      if (!span) return null
      return { band, spanId: span.id, style: this.spanStyle(span) }
    },
    hoverSpan() {
      const cell = this.hoverCell
      if (!cell) return null
      return (
        (this.rowSpans[cell.band] || []).find((sp) => sp.id === cell.spanId) ||
        null
      )
    },
    // The hovered slice per band, ready to redraw on top of the dimmed lane.
    hoverSlices() {
      const slot = this.hoverSlot
      if (!slot) return null
      const result = {}
      for (const key of this.rowKeys) {
        const g = this.sliceGeom(key, slot.seg, slot.start, slot.stop)
        if (g) {
          result[key] = {
            d: g.d,
            color: g.count > 0 ? rampColor(g.level) : CLEAR_STUB_COLOR,
          }
        }
      }
      return result
    },
    dragSelectionStyle() {
      if (this.dragStartPx === null) return null
      const left = Math.min(this.dragStartPx, this.dragCurrentPx)
      const width = Math.abs(this.dragCurrentPx - this.dragStartPx)
      return { left: `${left}px`, width: `${width}px` }
    },
    hasLoadedData() {
      return Object.values(this.stationEntries).some(Boolean)
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
      // Rows to show: the hovered row's band at every selected station (so
      // stations compare) - or, with no row under the cursor, every visible
      // band at the first station. Counts are the slot's worst minute - the
      // number the bar shows.
      const hoveredBand = this.hoverBand ? this.rowBand(this.hoverBand) : null
      const keys = hoveredBand
        ? this.rowKeys.filter((k) => this.rowBand(k) === hoveredBand)
        : this.rowKeys.filter(
            (k) => this.rowGs(k) === this.rowGs(this.rowKeys[0]),
          )
      const rows = keys.map((k) => {
        const b = this.rowBand(k)
        const count = this.slotCount(k, slot.start, slot.stop)
        const level = this.levelOf(count || 0, b)
        const label = this.multiStation
          ? hoveredBand
            ? this.stationNames[this.rowGs(k)] || this.rowGs(k)
            : b
          : b
        return {
          band: k,
          label,
          count: count === null ? '—' : count,
          color: count > 0 ? rampColor(level) : 'transparent',
          toneLabel:
            count === null
              ? 'No data'
              : count > 0
                ? `${Math.round(level * 100)}% of ${b} peak`
                : 'Clear',
        }
      })
      const bandSuffix =
        this.multiStation && hoveredBand ? ` · ${hoveredBand}` : ''
      const from = this.formatHM(this.idxToDate(slot.start))
      const to =
        slot.stop - slot.start > 1
          ? `–${this.formatHM(this.idxToDate(slot.stop - 1))}`
          : ''
      return {
        label: `${day.weekday} ${day.display} ${from}${to}${bandSuffix}`,
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
    selectedGroundStationIds: {
      handler(ids, old) {
        if (!ids || !ids.length) return
        if (
          old &&
          ids.length === old.length &&
          ids.every((v, i) => v === old[i])
        )
          return
        if (this.selectedSatelliteId) this.loadForecast()
      },
      deep: true,
    },
    use24h(v) {
      try {
        localStorage.setItem(TIME_24H_LS_KEY, v ? '1' : '0')
      } catch (e) {
        // ignore
      }
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
    rowHeightPx(band) {
      return this.rowHeights[band] || (this.multiStation ? 24 : 36)
    },
    inGrip(e) {
      const el = this.$refs.root
      if (!el) return false
      const r = el.getBoundingClientRect()
      return r.right - e.clientX <= GRIP_PX && r.bottom - e.clientY <= GRIP_PX
    },
    // A press in the grip corner starts a browser resize drag; when it ends
    // the size is remembered and the viewer's grid is told to re-flow.
    onRootMouseDown(e) {
      if (!this.inGrip(e)) return
      const onUp = () => {
        window.removeEventListener('mouseup', onUp)
        const el = this.$refs.root
        if (!el) return
        const r = el.getBoundingClientRect()
        const size = { w: Math.round(r.width) }
        this.userSize = size
        try {
          localStorage.setItem(SIZE_LS_KEY, JSON.stringify(size))
        } catch (err) {
          // private mode / quota: the size still holds for this page
        }
        // Telemetry Viewer lays its screens out with Muuri, which re-flows
        // on window resize but knows nothing about a screen changing size
        // on its own.
        window.dispatchEvent(new Event('resize'))
      }
      window.addEventListener('mouseup', onUp)
    },
    // Double-click on the grip corner: back to automatic size.
    onRootDblClick(e) {
      if (!this.inGrip(e)) return
      this.userSize = null
      try {
        localStorage.removeItem(SIZE_LS_KEY)
      } catch (err) {
        // ignore
      }
      this.$nextTick(() => window.dispatchEvent(new Event('resize')))
    },
    // Keeps laneWidthPx current so slotMinutes can size the slices to the
    // pixels actually available. No-op until the lanes element exists.
    observeLaneWidth() {
      const el = this.$refs.plot
      if (!el || el === this._laneObserved) return
      if (this._laneResizeObserver) this._laneResizeObserver.disconnect()
      this._laneObserved = el
      const rect = el.getBoundingClientRect()
      this.laneWidthPx = rect.width
      this.laneAreaPx = rect.height
      if (typeof ResizeObserver === 'undefined') return
      this._laneResizeObserver = new ResizeObserver((entries) => {
        const rect = entries[0]?.contentRect
        const w = rect?.width
        const h = rect?.height
        if (w && Math.abs(w - this.laneWidthPx) >= 1) this.laneWidthPx = w
        if (h && Math.abs(h - this.laneAreaPx) >= 1) this.laneAreaPx = h
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
        try {
          await this.api.cmd(
            'VEGA',
            'GET_APPROVED_ORGS',
            this.authOverride(),
            CMD_OPTS,
            CMD_KWARGS,
          )
        } catch (e) {
          if (!isAckTimeout(e)) throw e
        }
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
        // Prefer the row's own covered span (the box the user clicked) to
        // the union pass it sits in.
        if (seg) {
          const idx = seg.startIdx + Math.floor(c - seg.cstart)
          const sp = this.spanAt(band, idx)
          if (sp) seg = { cstart: sp.cstart, clen: sp.clen }
        }
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
      if (this.use24h) return `${pad2(p.hh)}:${pad2(p.mm)}`
      const h12 = p.hh % 12 || 12
      return `${h12}:${pad2(p.mm)} ${p.hh < 12 ? 'AM' : 'PM'}`
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
    buildBandBars(key, range = null) {
      const slot = this.slotMinutes
      const d = new Array(RAMP_STEPS + 1).fill('') // ramp steps + clear stubs
      for (const seg of this.segments) {
        for (let idx = seg.startIdx; idx < seg.endIdx; idx += slot) {
          const stop = Math.min(seg.endIdx, idx + slot)
          if (range) {
            const cx = seg.cstart + (idx - seg.startIdx) + (stop - idx) / 2
            if (cx < range[0] || cx > range[1]) continue
          }
          const g = this.sliceGeom(key, seg, idx, stop)
          if (g) d[g.step] += g.d
        }
      }
      return d
    },
    toggleBandOff(band) {
      this.selectedBands = this.selectedBands.filter((b) => b !== band)
    },
    removeStation(id) {
      this.selectedGroundStationIds = this.selectedGroundStationIds.filter(
        (v) => v !== id,
      )
    },
    rowBand(key) {
      return String(key).split('|')[0]
    },
    bandColor,
    bandTint,
    // The row's covered span containing minute idx, if any.
    spanAt(key, idx) {
      return (
        (this.rowSpans[key] || []).find(
          (sp) => idx >= sp.startIdx && idx < sp.endIdx,
        ) || null
      )
    },
    // A span's rect in the row SVG's user units, inset by half a pixel on
    // every side so the 1px non-scaling stroke stays inside the row.
    svgRect(span, band) {
      const view = Math.max(1, this.viewEnd - this.viewStart)
      const uxPerPx = view / (this.laneWidthPx || 1200)
      const rowPx = this.rowHeightPx(band) || 1
      const vbH = CHART_H * (1 + LANE_HEADROOM)
      const uyPerPx = vbH / rowPx
      return {
        x: span.cstart + uxPerPx * 0.5,
        y: -CHART_H * LANE_HEADROOM + uyPerPx * 0.5,
        width: Math.max(0, span.clen - uxPerPx),
        height: Math.max(0, vbH - uyPerPx),
        // 4px corners, matching the rest of the chart, in each axis' units
        rx: 4 * uxPerPx,
        ry: 4 * uyPerPx,
      }
    },
    spanWidthPx(span) {
      const view = Math.max(1, this.viewEnd - this.viewStart)
      return (span.clen / view) * (this.laneWidthPx || 1200)
    },
    spanStyle(span) {
      const row = this.rowGeometry[span.key] || { top: '0px', height: '46px' }
      const view = this.viewEnd - this.viewStart
      return {
        left: `${this.cToPct(span.cstart)}%`,
        width: `${(span.clen / view) * 100}%`,
        top: row.top,
        height: row.height,
      }
    },
    rowGs(key) {
      return String(key).split('|')[1]
    },
    rowEntries(key) {
      return this.stationEntries[this.rowGs(key)] || null
    },
    // Gap below a row: none after the last, GROUP_GAP_PX between bands,
    // LANE_GAP_PX between a band's station rows.
    rowGap(key) {
      const keys = this.rowKeys
      const i = keys.indexOf(key)
      if (i < 0 || i === keys.length - 1) return 0
      if (this.rowBand(keys[i + 1]) === this.rowBand(key)) return LANE_GAP_PX
      // The wide band-to-band gap makes room for the padded strips, which
      // only exist with several stations; one station keeps rows close.
      return this.multiStation ? GROUP_GAP_PX : LANE_GAP_PX
    },
    rowIsFirstOfBand(key) {
      const keys = this.rowKeys
      const i = keys.indexOf(key)
      return i <= 0 || this.rowBand(keys[i - 1]) !== this.rowBand(key)
    },
    // Places a {date => dayData} map's minutes on the window's minute grid.
    entriesFrom(dayDataByDate) {
      const map = new Array(this.totalMinutes).fill(null)
      const start = this.day0StartMs
      for (const dayData of Object.values(dayDataByDate || {})) {
        for (const entry of dayData.minutes || []) {
          const idx = Math.round(
            (new Date(entry.timestamp).getTime() - start) / 60000,
          )
          if (idx >= 0 && idx < map.length) map[idx] = entry
        }
      }
      return map
    },
    // A minute's count for a band, or null when there is no reading: the
    // minute isn't covered, or the API sent null because the run never
    // aggregated that band (no candidate interferer, or the band was added
    // after the run). 0 is a reading - analysed, nothing there.
    countOf(entry, band) {
      if (!entry || !entry.covered) return null
      const v = entry.counts ? entry.counts[band] : undefined
      if (v === null || v === undefined) return null
      const n = Number(v)
      return Number.isFinite(n) ? n : null
    },
    // Worst per-band count across the minutes [start, stop) - what a slot
    // shows, so grouping never hides a spike. null when no minute in the
    // slot has a reading.
    slotCount(key, start, stop) {
      const entries = this.rowEntries(key)
      const band = this.rowBand(key)
      if (!entries) return null
      let count = null
      for (let j = start; j < stop; j++) {
        const c = this.countOf(entries[j], band)
        if (c === null) continue
        if (count === null || c > count) count = c
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
    sliceGeom(key, seg, start, stop) {
      const count = this.slotCount(key, start, stop)
      if (count === null) return null // no reading: nothing to draw
      const clear = count === 0
      const level = clear ? 0 : this.levelOf(count, this.rowBand(key))
      const step = clear ? CLEAR_STEP : Math.round(level * (RAMP_STEPS - 1))
      const h = clear ? CLEAR_STUB_H * CHART_H : level * CHART_H
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
      this.selectedGroundStationIds = []
      this.stationDayData = {}
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
          this.selectedGroundStationIds = [this.groundStations[0].id]
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
        timeoutMs: 60000,
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
        timeoutMs: 60000,
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
    // window. Otherwise only days not already in the per-(satellite,
    // station, day) cache are fetched: today/forecast days expire after
    // FORECAST_CACHE_TTL_MS since the forecast keeps changing. One station
    // at a time (the interface is a serial pipe); rows fill in as each
    // station lands.
    async loadForecast(force = false) {
      if (!this.selectedSatelliteId || !this.selectedStations.length) return
      // Generation counter: selection changes can start a new load while an
      // old one is mid-flight; the stale load must stop writing so the chart
      // never mixes two selections' data.
      const gen = ++this._forecastGen
      this.errorText = ''
      this.zoomRange = null
      this.expandedBand = null
      const satId = this.selectedSatelliteId
      const stations = this.selectedStations
      const nowMs = Date.now()
      // Measured history (slow at Vega) is only offered for a single
      // station, and only merged from cache here; otherwise it waits for
      // the user (loadHistoryNow).
      this.pendingHistory = null
      let historyHit = null
      if (stations.length === 1) {
        const pastDays = this.utcFetchDays.filter((d) => d.past)
        const range = this.historyRange(pastDays)
        if (range) {
          historyHit = force === true ? null : this.historyCacheGet(range.key)
          if (!historyHit) this.pendingHistory = { pastDays, range, gen }
        }
      }
      // Cached days render immediately; only the rest are fetched.
      const next = {}
      const missing = []
      for (const gs of stations) {
        const byDate = {}
        if (historyHit) Object.assign(byDate, historyHit)
        for (const day of this.utcFetchDays) {
          const hit = this._dayCache[this.dayCacheKey(satId, gs.id, day)]
          const fresh = hit && nowMs - hit.at < FORECAST_CACHE_TTL_MS
          if (force !== true && fresh) byDate[day.date] = hit.data
          else missing.push({ gs, day })
        }
        next[gs.id] = byDate
      }
      this.stationDayData = next
      const total = missing.length
      if (total === 0) return
      this.loading = true
      let done = 0
      const failures = []
      try {
        for (const { gs, day } of missing) {
          this.progressText =
            stations.length > 1
              ? `Loading ${gs.name} ${day.date} (${done}/${total})`
              : `Loading ${day.date} (${done}/${total})`
          // Small pacing gap between requests - spreads the batch out to
          // reduce the odds of tripping whatever's causing the occasional
          // Net::ReadTimeout blips (likely rate limiting on rapid bursts).
          if (done > 0) {
            await new Promise((resolve) => setTimeout(resolve, 600))
          }
          try {
            const dayData = await this.fetchDayDetailWithRetry(
              satId,
              gs.id,
              day.date,
            )
            if (gen !== this._forecastGen) return
            this._dayCache[this.dayCacheKey(satId, gs.id, day)] = {
              at: Date.now(),
              data: dayData,
            }
            this.stationDayData = {
              ...this.stationDayData,
              [gs.id]: {
                ...(this.stationDayData[gs.id] || {}),
                [day.date]: dayData,
              },
            }
          } catch (e) {
            if (gen !== this._forecastGen) return
            failures.push(`${gs.name} ${day.date}: ${e.message}`)
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
    // The 'Load measured history' button: fetches the slice the current
    // window still lacks. Vega's history build takes 30-45s and blocks the
    // interface while it runs, so it only happens on request.
    async loadHistoryNow() {
      const pending = this.pendingHistory
      if (!pending || this.historyLoading) return
      const { pastDays, range } = pending
      this.historyLoading = true
      this.progressText = 'Loading measured history (Vega can take ~40s)'
      try {
        await this.loadHistory(
          this.selectedSatelliteId,
          this.selectedGroundStationId,
          this._forecastGen,
          pastDays,
          range,
        )
        if (this.pendingHistory === pending) this.pendingHistory = null
      } catch (e) {
        this.errorText = `History: ${e.message}`
      } finally {
        this.historyLoading = false
        if (!this.loading) this.progressText = ''
      }
    },
    // The measured-history request for a set of past UTC days: clipped to
    // the display window on both ends (a display day in a non-UTC zone
    // starts partway through a UTC day, and the rest of that UTC day is
    // not on screen), with a cache key that names the exact slice.
    historyRange(pastDays) {
      if (!pastDays?.length) return null
      const windowStart = this.day0StartMs
      const windowEnd = windowStart + this.totalMinutes * 60000
      const daysStart = new Date(`${pastDays[0].date}T00:00:00Z`).getTime()
      const daysEnd = new Date(
        `${this.dateAfter(pastDays[pastDays.length - 1].date)}T00:00:00Z`,
      ).getTime()
      // Whole seconds: the API echoes the range back without milliseconds
      const iso = (ms) => new Date(ms).toISOString().replace('.000Z', 'Z')
      const startIso = iso(Math.max(daysStart, windowStart))
      const endIso = iso(Math.min(daysEnd, windowEnd))
      return {
        startIso,
        endIso,
        key: `${this.selectedSatelliteId}|${this.selectedGroundStationId}|h|${startIso}|${endIso}`,
      }
    },
    // Immutable history slices live in memory and in localStorage, so a page
    // refresh (or coming back tomorrow) doesn't pay Vega's 30-45s again.
    historyCacheGet(key) {
      const mem = this._dayCache[key]
      if (mem) return mem.data
      try {
        const raw = localStorage.getItem(HISTORY_LS_PREFIX + key)
        if (!raw) return null
        const parsed = JSON.parse(raw)
        if (!parsed || typeof parsed.data !== 'object') return null
        this._dayCache[key] = parsed
        return parsed.data
      } catch (e) {
        return null
      }
    },
    historyCachePut(key, data) {
      const entry = { at: Date.now(), data }
      this._dayCache[key] = entry
      try {
        // Keep the store bounded: drop the oldest slices past the cap.
        const mine = Object.keys(localStorage)
          .filter((k) => k.startsWith(HISTORY_LS_PREFIX))
          .map((k) => {
            let at = 0
            try {
              at = JSON.parse(localStorage.getItem(k)).at || 0
            } catch (e) {
              // unreadable: treat as oldest
            }
            return { k, at }
          })
          .sort((a, b) => a.at - b.at)
        while (mine.length >= HISTORY_LS_MAX_ENTRIES) {
          localStorage.removeItem(mine.shift().k)
        }
        localStorage.setItem(HISTORY_LS_PREFIX + key, JSON.stringify(entry))
      } catch (e) {
        // quota or private mode: the in-memory copy still serves this session
      }
    },
    async loadHistory(
      satelliteId,
      groundStationId,
      gen,
      pastDays,
      range,
      attempts = 3,
    ) {
      if (!pastDays?.length || !range) return
      const { startIso, endIso } = range
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
              counts: normalizeBandKeys(point.counts || {}),
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
          }
          // Measured history is immutable - keep the whole slice.
          this.historyCachePut(range.key, merged)
          this.stationDayData = {
            ...this.stationDayData,
            [groundStationId]: {
              ...(this.stationDayData[groundStationId] || {}),
              ...merged,
            },
          }
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
          new Date(v.START_TIME).getTime() === new Date(startIso).getTime(),
        payload: ['TIMESERIES_JSON'],
        timeoutMs: 150000,
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
      try {
        await this.api.cmd(
          'VEGA',
          command,
          { ...this.authOverride(), ...params },
          CMD_OPTS,
          CMD_KWARGS,
        )
      } catch (e) {
        if (!isAckTimeout(e)) throw e
      }
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
        timeoutMs: 90000,
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
  box-sizing: border-box;
  color: var(--v-theme-on-surface, inherit);
  /* Browser resize grip in the bottom-right corner (see onRootMouseDown):
     width only - the rows have fixed heights */
  resize: horizontal;
  overflow: hidden;
}
.controls-col {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 8px;
}
.controls-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
/* Compact controls: 32px fields with 12px type, to leave the height to
   the chart. Vuetify sizes a compact field from --v-input-control-height. */
.controls-row :deep(.v-input) {
  --v-input-control-height: 32px;
}
.controls-row :deep(.v-field) {
  --v-field-input-padding-top: 4px;
  --v-field-input-padding-bottom: 4px;
  font-size: 12px;
}
.controls-row :deep(.v-input__control),
.controls-row :deep(.v-field),
.controls-row :deep(.v-field__field) {
  height: 32px !important;
  min-height: 32px !important;
}
.controls-row :deep(.v-field__input) {
  font-size: 12px;
  height: 32px !important;
  min-height: 32px !important;
  padding-top: 0 !important;
  padding-bottom: 0 !important;
  align-items: center;
}
.controls-row :deep(.v-select__selection-text) {
  font-size: 12px;
}
.controls-row :deep(.v-select__selection) {
  align-items: center;
}
.controls-row :deep(.v-select .v-field__input) {
  flex-wrap: nowrap;
  overflow: hidden;
}
.sel-text {
  font-size: 12px;
  white-space: nowrap;
}
.more-selected {
  font-size: 12px;
  opacity: 0.8;
  white-space: nowrap;
  margin-left: 2px;
}
.controls-row :deep(.v-chip) {
  height: 20px;
  font-size: 11px;
}
.controls-row :deep(.v-btn) {
  font-size: 12px;
}
.controls-row :deep(.v-field__append-inner),
.controls-row :deep(.v-field__prepend-inner) {
  padding-top: 0 !important;
  align-items: center;
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
.empty-bands-row {
  display: flex;
  justify-content: center;
  margin-top: 8px;
}
/* Quiet text actions (Reset zoom, show/hide bands with no data): plain
   muted text that only takes on the link colour when hovered */
.quiet-link {
  display: inline-flex;
  align-items: center;
  padding: 2px 6px;
  border: none;
  border-radius: 4px;
  background: transparent;
  color: inherit;
  opacity: 0.55;
  font-size: 11px;
  cursor: pointer;
}
.quiet-link.bordered {
  border: 1px solid rgba(128, 128, 128, 0.45);
  padding: 4px 10px;
}
.quiet-link:hover {
  opacity: 1;
  color: #4fc3f7;
  text-decoration: underline;
}
.build-stamp {
  font-size: 11px;
  opacity: 0.6;
}
.asi-info-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  margin-left: auto;
  padding: 2px 8px;
  border: none;
  border-radius: 999px;
  background: transparent;
  color: #4fc3f7;
  font-size: 11px;
  cursor: pointer;
}
.asi-info-btn:hover .asi-info-label {
  text-decoration: underline;
}
.asi-info-title {
  font-size: 18px;
}
.asi-info-body {
  font-size: 14px;
  line-height: 1.5;
  /* Capped so the dialog never outgrows the viewport; the body scrolls
     (v-dialog `scrollable` keeps the title and Close pinned) */
  max-height: 60vh;
  overflow-y: auto;
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
  margin-top: 14px;
}
.lanes-body {
  position: relative;
  display: flex;
}
.band-group-bg {
  position: absolute;
  /* 8px of air on every side of the band's rows: out past the band block
     on the left and the tracks on the right, and above / below the rows
     (bandGroups pads the top and bottom by the same amount) */
  left: -8px;
  right: -8px;
  z-index: 0;
  border-radius: 4px;
  pointer-events: none;
}
.lanes-labels,
.lanes-plots {
  position: relative;
  z-index: 1;
}
.lanes-labels {
  width: var(--label-w, 52px);
  flex: none;
  position: relative;
}
/* The band's header block: far left, spanning the band's rows */
.band-block {
  position: absolute;
  left: 0;
  width: 44px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
}
/* Per-row label (station name), right against the track; also the hover /
   click target for the row */
.lane-label {
  position: absolute;
  left: 52px;
  right: 8px;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  cursor: pointer;
  min-width: 0;
}
.lane-sub {
  font-size: 11px;
  opacity: 0.75;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
}
.lane-label.hovered .lane-sub {
  opacity: 1;
  font-weight: 600;
}
/* Expanded row: the name stays right-aligned like every other station
   label, sitting at the top above the count ticks */
.lane-label.expanded {
  align-items: flex-start;
  justify-content: flex-end;
  padding-top: 2px;
}
.lane-label .lane-name {
  font-size: 11px;
  opacity: 0.75;
  transition: opacity 0.1s ease;
}
.lane-label.hovered .lane-name {
  opacity: 1;
  font-weight: 600;
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
  /* Clip the zoomed-out boxes at the sides, but let the last row's
     bottom outline (which lands on the very last pixel) paint: the plot
     itself gets 2px of room below the rows and clips 2px past its box. */
  overflow: clip;
  overflow-clip-margin: 2px;
  padding-bottom: 2px;
}
/* The bars sit below the cell outlines, whatever the browser's default
   ordering of positioned siblings */
.lanes-stack {
  position: relative;
  z-index: 1;
}
.lane-plot {
  position: relative;
  transition: height 0.15s ease;
}
/* Grid cells: one outlined box per (pass, band), stacked to mirror the lane
   rows exactly (same heights, same row gap). The lanes draw no lines of
   their own, so nothing crosses the gaps. */
.pass-cell {
  position: absolute;
  box-sizing: border-box;
  overflow: hidden;
  /* The outline itself is drawn inside the row's SVG (see svgRect); this
     element only carries the Clear / No data note */
  border-radius: 4px;
  pointer-events: none;
  z-index: 3;
  transition: height 0.15s ease;
}
/* While busy, each control stays in the layout (so it keeps its exact
   width) but is hidden under a shimmer of the same size */
.ctl-wrap {
  position: relative;
  display: inline-flex;
}
.ctl-wrap.busy > :first-child {
  visibility: hidden;
}
.ctl-shimmer {
  position: absolute;
  inset: 0;
  border-radius: 4px;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0.05) 25%,
    rgba(255, 255, 255, 0.12) 50%,
    rgba(255, 255, 255, 0.05) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.4s ease-in-out infinite;
}
.skeleton-row {
  position: absolute;
  left: 0;
  right: 0;
  border-radius: 4px;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0.04) 25%,
    rgba(255, 255, 255, 0.11) 50%,
    rgba(255, 255, 255, 0.04) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.4s ease-in-out infinite;
  pointer-events: none;
}
@keyframes shimmer {
  0% {
    background-position: 200% 0;
  }
  100% {
    background-position: -200% 0;
  }
}
.cell-note {
  position: absolute;
  /* Sits in the lower half of the cell, just above the stub bars */
  inset: 30% 0 4px 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  opacity: 0.35;
  pointer-events: none;
}
.cell-note.clear {
  color: #43a047;
  opacity: 0.35;
  font-size: 9px;
  letter-spacing: 0.1em;
}
.empty-row {
  position: absolute;
  left: 0;
  right: 0;
  box-sizing: border-box;
  border: 1px solid rgba(128, 128, 128, 0.3);
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  opacity: 0.45;
  pointer-events: none;
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
  margin-top: 8px;
}
.x-axis-row.two-line {
  height: 30px;
}
.x-axis-spacer {
  width: var(--label-w, 48px); /* .lanes-labels */
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
  height: 32px;
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
  font-size: 12px;
  font-weight: 400;
  padding: 0 12px;
  color: var(--color-text-interactive-default) !important;
}
.quick-days .v-btn + .v-btn {
  border-left: 1px solid var(--color-border-interactive-muted);
}
/* Hover like the v-selects beside it: the border brightens (Vuetify lifts
   an outlined field's outline to high emphasis on hover) and nothing else
   changes - so no per-segment button overlay */
.quick-days:hover,
.cal-btn:hover:not(:disabled) {
  border-color: var(
    --color-border-interactive-hover,
    var(--color-text-interactive-default)
  );
}
.quick-days .v-btn .v-btn__overlay,
.quick-days .v-btn:hover .v-btn__overlay {
  opacity: 0 !important;
}
.quick-days .v-btn.v-btn--active {
  background-color: var(--color-background-surface-selected);
}
.cal-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 32px;
  padding: 0 10px;
  border: 1px solid var(--color-border-interactive-muted);
  border-radius: 4px;
  background-color: var(--color-background-base-default);
  color: var(--color-text-interactive-default);
  cursor: pointer;
  font-size: 12px;
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
  font-size: 12px;
  line-height: 14px;
  font-variant-numeric: tabular-nums;
  opacity: 0.85;
  white-space: nowrap;
  text-align: center;
}
.axis-divider {
  position: absolute;
  top: 1px;
  height: 12px;
  width: 0;
  border-left: 1px solid rgba(128, 128, 128, 0.45);
  pointer-events: none;
}
.hour-mark.align-start {
  transform: none;
  /* Equal clearance on both sides of the divider tick, which sits on the
     centre line of the gap between passes */
  padding-left: 6px;
}
.hour-mark.align-end {
  transform: translateX(-100%);
  padding-right: 6px;
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
  border-radius: 4px;
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
  border-radius: 4px;
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
