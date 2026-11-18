<template>
  <div>
    <h2 class="mb-4">MSEdit</h2>

    <v-skeleton-loader v-if="loading" :loading="true" type="card" />

    <div v-else style="margin-bottom: 80px">
      <v-alert v-if="error" type="error" variant="tonal" closable class="mb-4" @click:close="error = ''">
        {{ error }}
      </v-alert>

      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-file-document-edit-outline</v-icon>
          <span>Status</span>
          <v-spacer />
          <v-chip :color="status.installed ? 'success' : 'grey'" size="small" variant="tonal">
            {{ status.installed ? 'Installed' : 'Not installed' }}
          </v-chip>
        </v-card-title>
        <v-card-text>
          <v-row>
            <v-col cols="12" md="4">
              <div class="text-caption text-medium-emphasis">Installed</div>
              <div class="text-subtitle-1 font-weight-medium">{{ status.version || 'Not installed' }}</div>
            </v-col>
            <v-col cols="12" md="4">
              <div class="text-caption text-medium-emphasis">Command</div>
              <div class="text-subtitle-1 font-weight-medium"><code>msedit</code></div>
            </v-col>
          </v-row>

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn size="small" variant="text" @click="refreshAll">Refresh</v-btn>
          </div>
          <p class="text-caption text-medium-emphasis mt-2">
            Updates come through the MOS Hub plugin release.
          </p>
        </v-card-text>
      </v-card>

      <v-card class="pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-terminal</v-icon>
          <span>Use</span>
        </v-card-title>
        <v-card-text>
          <pre class="msedit-code">msedit
msedit /mnt/cache/some-file.txt</pre>
          <p class="text-caption text-medium-emphasis mt-2">
            An <code>edit</code> alias is also created when no system <code>edit</code> exists.
          </p>
        </v-card-text>
      </v-card>
    </div>

    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="4000">{{ snackbarText }}</v-snackbar>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue';

const PLUGIN_NAME = 'msedit';

const loading = ref(true);
const error = ref('');
const snackbar = ref(false);
const snackbarText = ref('');
const snackbarColor = ref('success');

const status = reactive({ installed: false, version: '', command: 'msedit' });

const authHeaders = () => ({ Authorization: 'Bearer ' + (localStorage.getItem('authToken') || '') });
const jsonHeaders = () => ({ ...authHeaders(), 'Content-Type': 'application/json' });

function notify(text, color = 'success') {
  snackbarText.value = text;
  snackbarColor.value = color;
  snackbar.value = true;
}

function setError(e) {
  error.value = e instanceof Error ? e.message : String(e);
  notify(error.value, 'error');
}

function parseOutput(data) {
  let output = data?.output;
  if (typeof output === 'string') {
    try { output = JSON.parse(output); } catch { /* keep string */ }
  }
  return output;
}

async function query(args, parseJson = false, timeout = 60) {
  const res = await fetch('/api/v1/mos/plugins/query', {
    method: 'POST',
    headers: jsonHeaders(),
    body: JSON.stringify({ command: PLUGIN_NAME, args, timeout, parse_json: parseJson }),
  });
  if (!res.ok) throw new Error(`Plugin query failed: HTTP ${res.status}`);
  const data = await res.json();
  if (data && data.success === false) throw new Error(data.error || data.message || 'Plugin query failed');
  return data;
}

async function refreshStatus() {
  const data = await query(['status'], true, 10);
  const out = parseOutput(data) || {};
  status.installed = out.installed === true;
  status.version = out.version || '';
  status.command = out.command || 'msedit';
}

async function refreshAll() {
  loading.value = true;
  try {
    await refreshStatus();
  } catch (e) {
    setError(e);
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await refreshAll();
});
</script>

<style scoped>
.msedit-code {
  background: rgba(0, 0, 0, 0.25);
  padding: 12px;
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.4;
}
</style>