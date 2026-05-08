<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke, type PeripheralsConf } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';

  let conf = $state<PeripheralsConf>({
    cur_theme: 'oxygen', cur_size: 20,
    fn_brightness_up: 'F2', fn_brightness_down: 'F1',
    fn_play_stop_play: 'F8', fn_play_next: 'F9', fn_play_prev: 'F7',
    fn_volume_up: 'F12', fn_volume_down: 'F11', fn_volume_mute: 'F10',
  });
  let themes = $state<string[]>([]);

  onMount(async () => {
    [conf, themes] = await Promise.all([
      invoke<PeripheralsConf>('read_peripherals_conf'),
      invoke<string[]>('get_cursor_themes'),
    ]);
  });

  async function applyCursor() {
    await invoke('hypr_set_cursor', { theme: conf.cur_theme, size: conf.cur_size });
  }

  async function onSave() {
    await invoke('write_peripherals_conf', { conf });
  }

  async function onReload() {
    await invoke('hypr_reload');
  }

  const fnKeys = [
    { label: 'Helligkeit hoch',   key: 'fn_brightness_up' as keyof PeripheralsConf },
    { label: 'Helligkeit runter', key: 'fn_brightness_down' as keyof PeripheralsConf },
    { label: 'Play / Pause',      key: 'fn_play_stop_play' as keyof PeripheralsConf },
    { label: 'Nächster Track',    key: 'fn_play_next' as keyof PeripheralsConf },
    { label: 'Vorheriger Track',  key: 'fn_play_prev' as keyof PeripheralsConf },
    { label: 'Lautstärke hoch',   key: 'fn_volume_up' as keyof PeripheralsConf },
    { label: 'Lautstärke runter', key: 'fn_volume_down' as keyof PeripheralsConf },
    { label: 'Stummschalten',     key: 'fn_volume_mute' as keyof PeripheralsConf },
  ];
</script>

<div class="page">
  <!-- Cursor -->
  <div class="card">
    <p class="section-title">Cursor</p>
    <div class="row">
      <div class="field">
        <label>Theme</label>
        <select bind:value={conf.cur_theme} onchange={applyCursor}>
          {#each themes as t}
            <option value={t}>{t}</option>
          {/each}
        </select>
      </div>
      <div class="field" style="max-width: 120px;">
        <label>Größe</label>
        <input
          type="number"
          bind:value={conf.cur_size}
          min="8" max="96"
          onchange={applyCursor}
        />
      </div>
    </div>
    <div class="cursor-preview">
      <span>Vorschau wird sofort angewendet</span>
    </div>
  </div>

  <!-- FN Keys -->
  <div class="card">
    <p class="section-title">FN-Tasten</p>
    <div class="fn-grid">
      {#each fnKeys as fn}
        <label>{fn.label}</label>
        <input bind:value={conf[fn.key] as string} placeholder="z.B. F8" />
      {/each}
    </div>
  </div>

  <SaveBar {onSave} {onReload} />
</div>

<style>
  .page { display: flex; flex-direction: column; gap: 12px; }
  .cursor-preview {
    margin-top: 8px;
    font-size: 11px;
    color: var(--text-muted);
    padding-top: 8px;
    border-top: 1px solid var(--border);
  }
  .fn-grid {
    display: grid;
    grid-template-columns: 1fr 140px;
    gap: 6px 12px;
    align-items: center;
  }
  .fn-grid label {
    text-transform: none;
    letter-spacing: 0;
    font-size: 13px;
    color: var(--text);
    margin: 0;
  }
</style>
