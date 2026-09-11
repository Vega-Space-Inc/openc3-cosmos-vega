<!--
# "Connect your Vega data": paste a frontend API key. The parent owns the
# saving state and the outcome (it talks to COSMOS); this only collects the
# key and reports it. Styles live in dialogs.css.
-->
<template>
  <v-dialog
    :model-value="modelValue"
    max-width="520"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <v-card class="asi-info">
      <v-card-title class="asi-info-title">Connect your Vega data</v-card-title>
      <v-card-text class="asi-info-body">
        <p>
          Paste a Vega <em>frontend</em> API key (it starts with
          <code>vgk_</code>) and the chart switches from the demo satellites to
          your organization's. The key stays in this browser; COSMOS masks it in
          logs and never stores it.
        </p>
        <form class="onboarding-keyform" @submit.prevent="submit">
          <div class="onboarding-keyrow">
            <input
              v-model="input"
              class="onboarding-input"
              type="password"
              placeholder="vgk_…"
              autocomplete="off"
              spellcheck="false"
              :disabled="saving"
            />
            <button
              type="submit"
              class="onboarding-save"
              :disabled="saving || !input.trim()"
            >
              {{ saving ? 'Checking…' : 'Connect' }}
            </button>
          </div>
          <div v-if="error" class="onboarding-error">
            {{ error }}
          </div>
        </form>
        <div class="asi-info-note keydlg-nokey">
          <p class="keydlg-nokey-text">No key yet?</p>
          <div class="keydlg-ctas">
            <v-btn
              color="primary"
              variant="flat"
              size="small"
              :href="signupUrl"
              target="_blank"
              rel="noopener"
            >
              Sign up
            </v-btn>
            <v-btn
              variant="outlined"
              size="small"
              :href="signinUrl"
              target="_blank"
              rel="noopener"
            >
              Sign in
            </v-btn>
          </div>
          <a
            class="keydlg-apikeys"
            :href="apiKeysUrl"
            target="_blank"
            rel="noopener"
            >API keys →</a
          >
        </div>
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
  name: 'ConnectKeyDialog',
  props: {
    modelValue: { type: Boolean, default: false },
    saving: { type: Boolean, default: false },
    error: { type: String, default: '' },
    apiKeysUrl: { type: String, required: true },
    signupUrl: { type: String, required: true },
    signinUrl: { type: String, required: true },
  },
  emits: ['update:modelValue', 'submit'],
  data() {
    return { input: '' }
  },
  watch: {
    // A closed dialog forgets what was typed
    modelValue(open) {
      if (!open) this.input = ''
    },
  },
  methods: {
    submit() {
      const key = this.input.trim()
      if (key) this.$emit('submit', key)
    },
  },
}
</script>
