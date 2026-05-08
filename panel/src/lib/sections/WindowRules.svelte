<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke, type WindowrulesConf } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';

  let conf = $state<WindowrulesConf>({ floating_window: '', opacity_window: '' });

  onMount(async () => {
    conf = await invoke<WindowrulesConf>('read_windowrules_conf');
  });

  async function onSave() {
    await invoke('write_windowrules_conf', { conf });
  }

  async function onReload() {
    await invoke('hypr_reload');
  }
</script>

<div class="page">
  <div class="card">
    <p class="section-title">Window Rule Variablen</p>
    <p class="hint">Regex-Pattern, mehrere Klassen mit <code>|</code> trennen.</p>

    <div class="field">
      <label>Floating Windows <code>$floating_window</code></label>
      <input bind:value={conf.floating_window} placeholder="(.*kitty.*|.*ark.*)" />
    </div>

    <div class="field">
      <label>Opaque Windows <code>$opacity_window</code></label>
      <input bind:value={conf.opacity_window} placeholder="(.*obsidian.*)" />
    </div>
  </div>
  <SaveBar {onSave} {onReload} />
</div>

<style>
  .page { display: flex; flex-direction: column; gap: 12px; }
  .hint { font-size: 12px; color: var(--text-muted); margin-bottom: 12px; }
  code {
    background: var(--bg-input); padding: 1px 5px;
    border-radius: 4px; font-size: 11px; color: var(--accent);
  }
</style>
