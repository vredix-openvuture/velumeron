<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke, type MonitorInfo, type MonitorsConf, type MonitorConf } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';
  import Toggle from '$lib/Toggle.svelte';

  const TRANSFORMS = [
    '0° – Normal', '90° – Im Uhrzeigersinn', '180°', '270° – Im Uhrzeigersinn',
    '0° – Gespiegelt', '90° – Gespiegelt', '180° – Gespiegelt', '270° – Gespiegelt',
  ];

  let liveMonitors = $state<MonitorInfo[]>([]);
  let conf = $state<MonitorsConf>({ mon1: '', mon2: null, monitors: [] });
  let activeIdx = $state(0);

  onMount(async () => {
    [liveMonitors, conf] = await Promise.all([
      invoke<MonitorInfo[]>('get_monitors'),
      invoke<MonitorsConf>('read_monitors_conf'),
    ]);
  });

  function modesFor(output: string): string[] {
    return liveMonitors.find(m => m.name === output)?.availableModes
      .map(m => m.replace(/Hz$/, ''))
      .sort((a, b) => {
        const rateA = parseFloat(a.split('@')[1] ?? '0');
        const rateB = parseFloat(b.split('@')[1] ?? '0');
        return rateB - rateA;
      }) ?? [];
  }

  async function liveKeyword(mon: MonitorConf, key: string, value: string) {
    await invoke('hypr_keyword', { keyword: `monitor:${mon.output} ${key}`, value }).catch(() => {});
  }

  async function onSave() {
    await invoke('write_monitors_conf', { conf });
  }

  async function onReload() {
    await invoke('hypr_reload');
  }
</script>

<div class="monitors-page">
  <!-- Monitor tabs -->
  <div class="mon-tabs">
    {#each conf.monitors as m, i}
      <button
        class="mon-tab {activeIdx === i ? 'active' : ''}"
        onclick={() => activeIdx = i}
      >
        {m.output}
        {#if liveMonitors.find(lm => lm.name === m.output)?.focused}
          <span class="dot"></span>
        {/if}
      </button>
    {/each}
  </div>

  {#if conf.monitors[activeIdx]}
    {@const m = conf.monitors[activeIdx]}
    {@const modes = modesFor(m.output)}

    <div class="card mon-card">
      <!-- Mode -->
      <div class="field">
        <label>Auflösung / Refresh Rate</label>
        {#if modes.length > 0}
          <select bind:value={m.mode} onchange={() => liveKeyword(m, 'mode', m.mode)}>
            {#each modes as mode}
              <option value={mode}>{mode}</option>
            {/each}
          </select>
        {:else}
          <input bind:value={m.mode} />
        {/if}
      </div>

      <!-- Transform -->
      <div class="field">
        <label>Ausrichtung (Transform)</label>
        <select
          value={m.transform}
          onchange={(e) => {
            m.transform = parseInt((e.target as HTMLSelectElement).value);
            liveKeyword(m, 'transform', String(m.transform));
          }}
        >
          {#each TRANSFORMS as t, i}
            <option value={i}>{t}</option>
          {/each}
        </select>
      </div>

      <div class="row">
        <!-- Position -->
        <div class="field">
          <label>Position (XxY)</label>
          <input bind:value={m.position} />
        </div>
        <!-- Scale -->
        <div class="field">
          <label>Scale</label>
          <select
            value={m.scale}
            onchange={(e) => {
              m.scale = parseFloat((e.target as HTMLSelectElement).value);
              liveKeyword(m, 'scale', String(m.scale));
            }}
          >
            {#each [1, 1.25, 1.5, 1.75, 2] as s}
              <option value={s}>{s}</option>
            {/each}
          </select>
        </div>
      </div>

      <div class="toggles">
        <div class="toggle-row">
          <span>HDR</span>
          <Toggle bind:checked={m.supports_hdr} />
        </div>
        <div class="toggle-row">
          <span>VRR (Adaptive Sync)</span>
          <Toggle
            bind:checked={m.vrr}
            onchange={(v) => liveKeyword(m, 'vrr', v ? 'on' : 'off')}
          />
        </div>
      </div>
    </div>
  {/if}

  <SaveBar {onSave} {onReload} />
</div>

<style>
  .monitors-page { display: flex; flex-direction: column; height: 100%; }
  .mon-tabs { display: flex; gap: 4px; margin-bottom: 12px; }
  .mon-tab {
    padding: 6px 16px;
    border-radius: 6px;
    background: var(--bg-input);
    color: var(--text-muted);
    border: 1px solid var(--border);
    cursor: pointer;
    font-size: 13px;
    display: flex; align-items: center; gap: 6px;
  }
  .mon-tab.active { background: var(--accent); color: #fff; border-color: var(--accent); }
  .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--green); }
  .mon-card { flex: 1; }
  .toggles { display: flex; flex-direction: column; gap: 4px; }
  .toggle-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 8px 0;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
  }
  .toggle-row:last-child { border-bottom: none; }
</style>
