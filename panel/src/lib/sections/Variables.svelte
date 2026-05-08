<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke, type VariablesConf } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';

  let conf = $state<VariablesConf>({
    desktop_shell: '', notify_service: '', launcher: '', theme_switch: '',
    terminal: '', notifications: '', screenshot: '', on_sleep: '', on_lock: '', session_menu: '',
  });

  onMount(async () => {
    conf = await invoke<VariablesConf>('read_variables_conf');
  });

  const fields: { label: string; key: keyof VariablesConf }[] = [
    { label: 'Desktop Shell',     key: 'desktop_shell' },
    { label: 'Notify Service',    key: 'notify_service' },
    { label: 'Launcher',          key: 'launcher' },
    { label: 'Theme Switch',      key: 'theme_switch' },
    { label: 'Terminal',          key: 'terminal' },
    { label: 'Notifications',     key: 'notifications' },
    { label: 'Screenshot',        key: 'screenshot' },
    { label: 'Sleep',             key: 'on_sleep' },
    { label: 'Lock',              key: 'on_lock' },
    { label: 'Session Menu',      key: 'session_menu' },
  ];

  async function onSave() {
    await invoke('write_variables_conf', { conf });
  }

  async function onReload() {
    await invoke('hypr_reload');
  }
</script>

<div class="page">
  <div class="card">
    <p class="section-title">App-Variablen</p>
    {#each fields as f}
      <div class="field">
        <label>{f.label}</label>
        <input bind:value={conf[f.key] as string} />
      </div>
    {/each}
  </div>
  <SaveBar {onSave} {onReload} />
</div>

<style>
  .page { display: flex; flex-direction: column; gap: 12px; }
</style>
