<!--
# Onboarding tour overlay: the page dims except for a spotlighted region
# (frame + corner brackets) with a themed card of copy beside it - the same
# shape as the Vega app's forecast tour. The parent decides the steps,
# measures the targets and positions the card; this draws it. Teleported to
# <body> so a transformed grid container can't trap the fixed positioning.
-->
<template>
  <teleport to="body">
    <div v-if="active && rect" class="tour-layer">
      <div class="tour-shield" />
      <div
        class="tour-frame"
        :style="{
          top: rect.top + 'px',
          left: rect.left + 'px',
          width: rect.width + 'px',
          height: rect.height + 'px',
        }"
      >
        <span class="tour-dash" />
        <span class="tour-corner tl" />
        <span class="tour-corner tr" />
        <span class="tour-corner bl" />
        <span class="tour-corner br" />
      </div>
      <v-card
        ref="tourCard"
        class="tour-card asi-info"
        :style="{
          top: cardPos.top + 'px',
          left: cardPos.left + 'px',
        }"
        aria-label="Widget tour"
      >
        <v-card-title class="asi-info-title tour-title-row">
          <span>{{ step.title }}</span>
          <span class="tour-count">{{ index + 1 }} / {{ total }}</span>
        </v-card-title>
        <v-card-text :key="step.id" class="asi-info-body tour-text">
          {{ step.body }}
        </v-card-text>
        <v-card-actions>
          <v-btn variant="text" size="small" @click="$emit('skip')">
            Skip tour
          </v-btn>
          <v-spacer />
          <v-btn
            v-if="index > 0"
            variant="outlined"
            size="small"
            @click="$emit('back')"
          >
            Back
          </v-btn>
          <v-btn
            color="primary"
            variant="flat"
            size="small"
            @click="$emit('next')"
          >
            {{ index >= total - 1 ? 'Done' : 'Next' }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </div>
  </teleport>
</template>

<script>
export default {
  name: 'TourOverlay',
  props: {
    active: { type: Boolean, default: false },
    rect: { type: Object, default: null },
    cardPos: { type: Object, default: () => ({ top: 0, left: 0 }) },
    step: { type: Object, default: () => ({ id: '', title: '', body: '' }) },
    index: { type: Number, default: 0 },
    total: { type: Number, default: 0 },
  },
  emits: ['skip', 'back', 'next'],
  methods: {
    // The card's rendered height, for the parent's placement maths
    cardHeight() {
      const c = this.$refs.tourCard
      const el = c && (c.$el || c)
      return el && el.offsetHeight ? el.offsetHeight : 0
    },
  },
}
</script>

<style lang="scss" scoped>
/* ---- Onboarding tour (teleported to <body>) ---- */
.tour-layer {
  position: fixed;
  inset: 0;
  z-index: 9000;
  animation: tour-fade 0.3s ease;
}
@keyframes tour-fade {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}
.tour-shield {
  position: absolute;
  inset: 0;
}
.tour-frame {
  position: absolute;
  color: rgb(var(--v-theme-secondary));
  box-shadow: 0 0 0 100vmax rgba(var(--v-theme-background), 0.82);
  border-radius: 4px;
  pointer-events: none;
  transition:
    top 0.3s ease,
    left 0.3s ease,
    width 0.3s ease,
    height 0.3s ease;
}
.tour-dash {
  position: absolute;
  inset: 0;
  border: 1px dashed currentColor;
  border-radius: 4px;
  opacity: 0.45;
}
.tour-corner {
  position: absolute;
  width: 14px;
  height: 14px;
  border-color: currentColor;
  border-style: solid;
  border-width: 0;
}
.tour-corner.tl {
  top: -1px;
  left: -1px;
  border-top-width: 2px;
  border-left-width: 2px;
}
.tour-corner.tr {
  top: -1px;
  right: -1px;
  border-top-width: 2px;
  border-right-width: 2px;
}
.tour-corner.bl {
  bottom: -1px;
  left: -1px;
  border-bottom-width: 2px;
  border-left-width: 2px;
}
.tour-corner.br {
  bottom: -1px;
  right: -1px;
  border-bottom-width: 2px;
  border-right-width: 2px;
}
.tour-card {
  position: absolute !important;
  width: 320px;
  transition:
    top 0.3s ease,
    left 0.3s ease;
}
.tour-title-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
}
.tour-count {
  font-size: 11px;
  font-weight: 400;
  opacity: 0.55;
  white-space: nowrap;
}
.tour-text {
  padding-top: 10px !important;
}
</style>
