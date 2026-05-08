<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke, type AutostartConf } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';

  let conf = $state<AutostartConf>({ daemons: [], scripts: [], apps: [], app_workspaces: [] });
  let tab = $state<'daemons' | 'scripts' | 'apps'>('apps');

  onMount(async () => {
    conf = await invoke<AutostartConf>('read_autostart_conf');
  });

  function removeItem(list: string[], i: number) {
    list.splice(i, 1);
  }

  let newDaemon = $state('');
  let newScript = $state('');

  function addDaemon() {
    if (!newDaemon.trim()) return;
    conf.daemons.push(newDaemon.trim());
    newDaemon = '';
  }

  function addScript() {
    if (!newScript.trim()) return;
    conf.scripts.push(newScript.trim());
    newScript = '';
  }

  async function onSave() {
    await invoke('write_autostart_conf', { conf });
  }
</script>

<div class="page">
  <div class="tabs">
    {#each (['apps', 'daemons', 'scripts'] as const) as t}
      <button class="tab {tab === t ? 'active' : ''}" onclick={() => tab = t}>
        {t === 'apps' ? 'Workspace-Apps' : t === 'daemons' ? 'Daemons' : 'Scripts'}
      </button>
    {/each}
  </div>

  {#if tab === 'apps'}
    <div class="card apps-card">
      <div class="apps-header">
        <span>Slot</span><span>Workspace</span><span>Befehl</span>
      </div>
      {#each conf.apps as _, i}
        <div class="app-row">
          <span class="slot-num">{i + 1}</span>
          <input
            type="number"
            class="ws-input"
            bind:value={conf.app_workspaces[i]}
            min="1"
          />
          <input
            class="cmd-input"
            bind:value={conf.apps[i]}
            placeholder="(leer = deaktiviert)"
          />
        </div>
      {/each}
    </div>

  {:else if tab === 'daemons'}
    <div class="card list-card">
      {#each conf.daemons as d, i}
        <div class="list-row">
          <input bind:value={conf.daemons[i]} />
          <button class="btn-danger small" onclick={() => removeItem(conf.daemons, i)}>✕</button>
        </div>
      {/each}
      <div class="add-row">
        <input bind:value={newDaemon} placeholder="exec-once Befehl…" onkeydown={(e) => e.key === 'Enter' && addDaemon()} />
        <button class="btn-primary small" onclick={addDaemon}>+</button>
      </div>
    </div>

  {:else}
    <div class="card list-card">
      {#each conf.scripts as s, i}
        <div class="list-row">
          <input bind:value={conf.scripts[i]} />
          <button class="btn-danger small" onclick={() => removeItem(conf.scripts, i)}>✕</button>
        </div>
      {/each}
      <div class="add-row">
        <input bind:value={newScript} placeholder="Script-Befehl…" onkeydown={(e) => e.key === 'Enter' && addScript()} />
        <button class="btn-primary small" onclick={addScript}>+</button>
      </div>
    </div>
  {/if}

  <SaveBar {onSave} />
</div>

<style>
  .page { display: flex; flex-direction: column; gap: 12px; height: 100%; }
  .tabs { display: flex; gap: 4px; }
  .tab {
    padding: 6px 14px; border-radius: 6px; cursor: pointer; font-size: 13px;
    background: var(--bg-input); color: var(--text-muted); border: 1px solid var(--border);
  }
  .tab.active { background: var(--accent); color: #fff; border-color: var(--accent); }
  .apps-card, .list-card { flex: 1; overflow-y: auto; }
  .apps-header {
    display: grid; grid-template-columns: 40px 80px 1fr;
    gap: 8px; padding: 0 0 8px;
    font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;
    color: var(--text-muted); border-bottom: 1px solid var(--border);
    margin-bottom: 4px;
  }
  .app-row {
    display: grid; grid-template-columns: 40px 80px 1fr;
    gap: 8px; align-items: center;
    padding: 4px 0; border-bottom: 1px solid var(--border);
  }
  .app-row:last-child { border-bottom: none; }
  .slot-num { font-weight: 600; color: var(--accent); text-align: center; }
  .ws-input { width: 100%; }
  .cmd-input { width: 100%; }
  .list-row { display: flex; gap: 8px; align-items: center; padding: 4px 0; border-bottom: 1px solid var(--border); }
  .add-row { display: flex; gap: 8px; align-items: center; padding-top: 8px; }
  .small { padding: 6px 10px; flex-shrink: 0; }
</style>
