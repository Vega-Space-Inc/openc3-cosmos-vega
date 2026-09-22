<!--
# Copyright 2026 Vega Space, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from Vega Space, Inc.
-->
<!--
# "Connect your Vega data": how the plugin gets its API key. Nothing is
# entered here - the key lives in COSMOS Admin / Secrets, which has its own
# permissions and audit trail; this explains the two steps, links there, and
# re-checks. The parent owns the check (it talks to COSMOS) and reports what
# it found through the props. Styles live in dialogs.css.
-->
<template>
  <v-dialog
    :model-value="modelValue"
    max-width="560"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <v-card class="asi-info">
      <v-card-title class="asi-info-title">Connect your Vega data</v-card-title>
      <v-card-text class="asi-info-body">
        <p>
          This COSMOS uses one Vega API key, kept as the
          <code>{{ secretName }}</code> secret in Admin → Secrets. Once it
          holds a valid <em>frontend</em> key, the chart shows that key's
          organizations instead of the demo satellites. The key never passes
          through this page.
        </p>
        <div v-if="statusText" class="keydlg-status" :class="statusClass">
          {{ statusText }}
        </div>
        <ol class="keydlg-steps">
          <li>
            Create a frontend API key (it starts with <code>vgk_</code>) at
            <a :href="apiKeysUrl" target="_blank" rel="noopener"
              >app.vega.space/settings/api-keys</a
            >.
          </li>
          <li>
            Have a COSMOS admin add it in Admin → Secrets as
            <code>{{ secretName }}</code> - or update it there if the key
            expired. It takes effect on the next request; no restart.
          </li>
          <li>Check again.</li>
        </ol>
        <div class="keydlg-ctas">
          <v-btn
            color="primary"
            variant="flat"
            size="small"
            :href="secretsUrl"
            target="_blank"
            rel="noopener"
          >
            Open Admin → Secrets
          </v-btn>
          <v-btn
            variant="outlined"
            size="small"
            :loading="checking"
            @click="$emit('check')"
          >
            Check again
          </v-btn>
        </div>
        <div class="asi-info-note keydlg-nokey">
          <p class="keydlg-nokey-text">No Vega account yet?</p>
          <div class="keydlg-ctas">
            <v-btn
              variant="outlined"
              size="small"
              :href="signupUrl"
              target="_blank"
              rel="noopener"
            >
              Sign up
            </v-btn>
            <v-btn
              variant="text"
              size="small"
              :href="signinUrl"
              target="_blank"
              rel="noopener"
            >
              Sign in
            </v-btn>
          </div>
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
    // 'unknown' | 'ok' | 'invalid' | 'error' | 'unavailable' - see the
    // widget's sharedKey
    sharedKey: { type: String, default: 'unknown' },
    status: { type: Number, default: null },
    detail: { type: String, default: '' },
    checking: { type: Boolean, default: false },
    secretName: { type: String, required: true },
    secretsUrl: { type: String, required: true },
    apiKeysUrl: { type: String, required: true },
    signupUrl: { type: String, required: true },
    signinUrl: { type: String, required: true },
  },
  emits: ['update:modelValue', 'check'],
  computed: {
    statusText() {
      const detail = this.detail ? `: ${this.detail}` : ''
      switch (this.sharedKey) {
        case 'ok':
          return `The ${this.secretName} secret works - the chart shows its organizations.`
        case 'invalid':
          return `Vega rejected the ${this.secretName} secret (HTTP 401${detail}). It does not exist yet, or the key in it has expired.`
        case 'error':
          return `Vega answered HTTP ${this.status || '?'}${detail} on the ${this.secretName} secret.`
        case 'unavailable':
          return 'The last check got no answer - is the VEGA_INT interface connected?'
        default:
          return ''
      }
    },
    statusClass() {
      return this.sharedKey === 'ok' ? 'keydlg-status-ok' : 'keydlg-status-bad'
    },
  },
}
</script>
