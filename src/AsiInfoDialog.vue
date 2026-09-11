<!--
# "ASI Risk Overview": what adjacent satellite interference is and how Vega
# forecasts it, from the forecasting technical brief. Styles in dialogs.css.
-->
<template>
  <v-dialog
    :model-value="modelValue"
    max-width="600"
    scrollable
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <v-card class="asi-info">
      <v-card-title class="asi-info-title">ASI Risk Overview</v-card-title>
      <v-card-text class="asi-info-body">
        <p>
          <strong>Adjacent satellite interference (ASI)</strong> is the risk
          that another satellite transmitting in the same frequency band is in
          your ground station's view at the same time as the satellite you are
          tracking, so its signal can land in your receiver alongside the one
          you want. Vega models all 15,000+ active satellites - their orbits,
          their frequencies, their beam patterns - and forecasts where and when
          transmissions will overlap, up to three days ahead.
        </p>

        <h4>How the forecast is built</h4>
        <ol>
          <li>
            <strong>Orbital tracking.</strong> Two-Line Element sets from
            authoritative sources, refreshed daily, are propagated forward with
            industry-standard orbital mechanics that account for atmospheric
            drag, Earth's oblateness (J2) and solar radiation pressure.
          </li>
          <li>
            <strong>Frequency conflict identification.</strong> Only satellites
            operating in overlapping bands can interfere. Satellites are mapped
            to their frequency allocations from regulatory databases and public
            filings, and only confirmed overlaps or recorded usages are flagged
            as potential interferers.
          </li>
          <li>
            <strong>Coverage analysis.</strong> Each satellite's field of regard
            is modelled as a cone tangent to Earth's surface over an equal-area
            HEALPix grid at roughly 100 km resolution, for every minute of the
            three-day window - 4,320 epochs per analysis.
          </li>
          <li>
            <strong>Interference event detection.</strong> For each minute, your
            satellite's footprint and every potential interferer's footprint are
            computed and their intersections found - the areas where both are in
            view at once.
          </li>
          <li>
            <strong>Aggregation per band.</strong> The resulting matrices (epoch
            × interfering satellite) are combined per operating band into a
            per-cell intensity for every epoch. The count behind each bar here
            is that intensity read at your ground station's cell: how many
            same-band satellites share its sky that minute.
          </li>
        </ol>

        <h4>Reading this chart</h4>
        <ul>
          <li>
            Each bar is one minute (or a few minutes when the view is too narrow
            to show them individually - the tooltip then says which). Height and
            colour are that minute's count relative to the band's busiest minute
            in the loaded day, from green (quiet) through amber to red (the
            peak). The tooltip gives the actual count.
          </li>
          <li>
            A flat row of green stubs means the band was analysed and found
            clear. An empty box means there is no reading for that band in that
            pass.
          </li>
          <li>
            Today and the next two days come from the latest forecast run;
            earlier days are the measured record. Only time when the satellite
            is in view of the station is shown - the gaps between passes are
            removed.
          </li>
        </ul>

        <h4>Validation and limits</h4>
        <ul>
          <li>
            Orbital data is refreshed daily; predictions degrade beyond three
            days, which is why the forecast stops there.
          </li>
          <li>
            Frequency mappings carry confidence levels based on the quality of
            their source.
          </li>
          <li>
            Telemetry and ground readings feed a learning layer that refines the
            models and confidence scoring over time.
          </li>
          <li>
            Some things cannot be predicted: solar storms, unannounced satellite
            manoeuvres and intentional jamming.
          </li>
        </ul>
        <p class="asi-info-note">
          Counts are geometric and spectral - they say how many same-band
          satellites share the station's sky, not the received power of each.
          Treat a high count as a cue to check the pass, not as a measured
          carrier-to-interference ratio.
        </p>
      </v-card-text>
      <v-card-actions>
        <v-spacer />
        <v-btn variant="text" @click="$emit('update:modelValue', false)"
          >Close</v-btn
        >
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  name: 'AsiInfoDialog',
  props: { modelValue: { type: Boolean, default: false } },
  emits: ['update:modelValue'],
}
</script>
