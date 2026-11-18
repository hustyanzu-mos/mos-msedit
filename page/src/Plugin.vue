<template>
  <div>
    <h2 class="mb-4">msedit</h2>

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
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Installed</div>
              <div class="text-subtitle-1 font-weight-medium">{{ status.version || 'Not installed' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Latest</div>
              <div class="text-subtitle-1 font-weight-medium">{{ latestVersion || '-' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Command</div>
              <div class="text-subtitle-1 font-weight-medium"><code>msedit</code></div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">ICU</div>
              <div class="text-subtitle-1 font-weight-medium">
                <v-chip :color="status.icu.installed ? 'success' : 'warning'" size="small" variant="tonal">
                  {{ icuLabel }}
                </v-chip>
              </div>
            </v-col>
          </v-row>

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn size="small" variant="tonal" color="secondary" :loading="checking" @click="checkForUpdates">
              Check updates
            </v-btn>
            <v-btn v-if="!status.installed" size="small" color="primary" :loading="installing" @click="installCore">
              Install
            </v-btn>
            <v-btn v-else-if="updateAvailable" size="small" color="primary" :loading="updating" @click="updateCore">
              Update to {{ latestVersion }}
            </v-btn>
            <v-btn v-if="!status.icu.installed" size="small" color="warning" variant="tonal" :loading="installingIcu" @click="installIcu">
              Install ICU
            </v-btn>
            <v-btn size="small" variant="text" @click="refreshAll">Refresh</v-btn>
          </div>
        </v-card-text>
      </v-card>

      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-information-outline</v-icon>
          <span>ICU runtime</span>
        </v-card-title>
        <v-card-text>
          <p class="text-body-2 text-medium-emphasis">
            msedit uses ICU for search and replace. The plugin looks for a system ICU first;
            if it is missing, it downloads the matching Devuan package and extracts the
            libraries into the persistent plugin directory.
          </p>
          <p class="text-body-2 mt-3">
            Source: <strong>{{ status.icu.source }}</strong>
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
            The wrapper sets <code>LD_LIBRARY_PATH</code> to the plugin ICU directory.
            An <code>edit</code> alias is also created when no system <code>edit</code> exists.
          </p>
        </v-card-text>
      </v-card>
    </div>

    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="4000">{{ snackbarText }}</v-snackbar>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue';

const PLUGIN_NAME = 'msedit';
const DEFAULT_SETTINGS = { auto_install: true, pin_version: '', version: '' };

const loading = ref(true);
const checking = ref(false);
const installing = ref(false);
const updating = ref(false);
const installingIcu = ref(false);
const error = ref('');
const snackbar = ref(false);
const snackbarText = ref('');
const snackbarColor = ref('success');

const settings = reactive({ ...DEFAULT_SETTINGS });
const status = reactive({
  installed: false,
  version: '',
  icu: { installed: false, source: 'missing' },
  command: 'msedit',
});
const latestVersion = ref('');
const updateAvailable = ref(false);

const icuLabel = computed(() => {
  if (!status.icu.installed) return 'Missing';
  return status.icu.source === 'system' ? 'System' : 'Bundled';
});

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

async function fetchSettings() {
  const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, { headers: authHeaders() });
  if (!res.ok) throw new Error(`Settings request failed: HTTP ${res.status}`);
  const raw = await res.json();
  const data = raw && raw.data && typeof raw.data === 'object' ? raw.data : raw;
  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    if (data[key] !== undefined && data[key] !== null) settings[key] = data[key];
  }
}

async function refreshStatus() {
  const data = await query(['status'], true, 10);
  const out = parseOutput(data) || {};
  status.installed = out.installed === true;
  status.version = out.version || '';
  status.command = out.command || 'msedit';
  status.icu = out.icu || { installed: false, source: 'missing' };
  if (out.version && out.version !== 'not installed') settings.version = out.version;
}

async function checkForUpdates() {
  checking.value = true;
  try {
    const data = await query(['check_version'], true, 30);
    const out = parseOutput(data) || {};
    latestVersion.value = out.latest || '';
    updateAvailable.value = status.installed && out.update_available === true;
  } catch (e) {
    setError(e);
  } finally {
    checking.value = false;
  }
}

async function refreshAll() {
  loading.value = true;
  try {
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
  } catch (e) {
    setError(e);
  } finally {
    loading.value = false;
  }
}

async function installCore() {
  installing.value = true;
  try {
    await query(['install_binary', 'latest'], false, 180);
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
    notify('msedit installed');
  } catch (e) {
    setError(e);
  } finally {
    installing.value = false;
  }
}

async function updateCore() {
  updating.value = true;
  try {
    await query(['install_binary', 'latest'], false, 180);
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
    notify('msedit updated');
  } catch (e) {
    setError(e);
  } finally {
    updating.value = false;
  }
}

async function installIcu() {
  installingIcu.value = true
  try {
    await query(['install_icu'], false, 180);
    await refreshStatus();
    notify('ICU installed');
  } catch (e) {
    setError(e);
  } finally {
    installingIcu.value = false;
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