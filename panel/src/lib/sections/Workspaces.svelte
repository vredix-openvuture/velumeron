<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke, type WorkspaceEntry } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';
  import Toggle from '$lib/Toggle.svelte';

  let workspaces = $state<WorkspaceEntry[]>([]);
  let monitors = $state<string[]>([]);
  let selectedMon = $state('');
  let newNum = $state('');
  let newMon = $state('');

  onMount(async () => {
    workspaces = await invoke<WorkspaceEntry[]>('read_workspaces_conf');
    const lm = await invoke<{ name: string }[]>('get_monitors');
    monitors = lm.map(m => m.name);
    // derive monitor var names from workspaces
    const monVars = [...new Set(workspaces.map(w => w.monitor))];
    if (monVars.length > 0) selectedMon = monVars[0];
    newMon = selectedMon;
  });

  const monVars = $derived([...new Set(workspaces.map(w => w.monitor))].sort());
  const filtered = $derived(
    workspaces.filter(w => !selectedMon || w.monitor === selectedMon)
      .sort((a, b) => a.num - b.num)
  );

  async function addWorkspace() {
    const num = parseInt(newNum);
    if (isNaN(num) || num < 1) return;
    if (workspaces.some(w => w.num === num)) return;
    const entry: WorkspaceEntry = { num, monitor: newMon || selectedMon, persistent: true, default: false };
    await invoke('write_workspace', { entry });
    workspaces = await invoke<WorkspaceEntry[]>('read_workspaces_conf');
    newNum = '';
  }

  async function removeWorkspace(num: number) {
    await invoke('remove_workspace', { num });
    workspaces = await invoke<WorkspaceEntry[]>('read_workspaces_conf');
  }

  async function togglePersistent(entry: WorkspaceEntry) {
    const updated = { ...entry, persistent: !entry.persistent };
    await invoke('write_workspace', { entry: updated });
    workspaces = await invoke<WorkspaceEntry[]>('read_workspaces_conf');
  }

  async function onSave() {
    // already written live via write_workspace
  }

  async function onReload() {
    await invoke('hypr_reload');
  }
</script>

<div class="ws-page">
  <!-- Monitor selector -->
  <div class="mon-tabs">
    {#each monVars as mv}
      <button
        class="mon-tab {selectedMon === mv ? 'active' : ''}"
        onclick={() => selectedMon = mv}
      >
        {mv}
        <span class="count">{workspaces.filter(w => w.monitor === mv).length}</span>
      </button>
    {/each}
  </div>

  <!-- Workspace list -->
  <div class="ws-list card">
    <div class="ws-header">
      <span>Nr.</span>
      <span>Monitor</span>
      <span>Persistent</span>
      <span>Default</span>
      <span></span>
    </div>
    {#each filtered as ws}
      <div class="ws-row">
        <span class="num">{ws.num}</span>
        <span class="tag">{ws.monitor}</span>
        <Toggle
          checked={ws.persistent}
          onchange={() => togglePersistent(ws)}
        />
        <span class="tag {ws.default ? 'on' : 'off'}">{ws.default ? '★ default' : '–'}</span>
        <button class="btn-danger small" onclick={() => removeWorkspace(ws.num)}>✕</button>
      </div>
    {/each}

    {#if filtered.length === 0}
      <div class="empty">Keine Workspaces für diesen Monitor.</div>
    {/if}
  </div>

  <!-- Add workspace -->
  <div class="card add-card">
    <p class="section-title">Workspace hinzufügen</p>
    <div class="row">
      <div class="field">
        <label>Nummer</label>
        <input type="number" bind:value={newNum} min="1" placeholder="z.B. 11" />
      </div>
      <div class="field">
        <label>Monitor</label>
        <select bind:value={newMon}>
          {#each monVars as mv}
            <option value={mv}>{mv}</option>
          {/each}
        </select>
      </div>
      <div style="align-self: flex-end; padding-bottom: 14px;">
        <button class="btn-primary" onclick={addWorkspace}>Hinzufügen</button>
      </div>
    </div>
  </div>

  <SaveBar {onSave} {onReload} />
</div>

<style>
  .ws-page { display: flex; flex-direction: column; gap: 12px; height: 100%; }
  .mon-tabs { display: flex; gap: 4px; }
  .mon-tab {
    padding: 6px 14px; border-radius: 6px;
    background: var(--bg-input); color: var(--text-muted);
    border: 1px solid var(--border); cursor: pointer;
    display: flex; align-items: center; gap: 6px; font-size: 13px;
  }
  .mon-tab.active { background: var(--accent); color: #fff; border-color: var(--accent); }
  .count {
    background: rgba(255,255,255,0.15);
    border-radius: 10px; padding: 0 6px; font-size: 11px;
  }
  .ws-list { flex: 1; overflow-y: auto; }
  .ws-header, .ws-row {
    display: grid;
    grid-template-columns: 50px 1fr 80px 100px 36px;
    align-items: center;
    gap: 8px;
    padding: 6px 0;
  }
  .ws-header {
    font-size: 10px; text-transform: uppercase;
    letter-spacing: 0.06em; color: var(--text-muted);
    border-bottom: 1px solid var(--border); padding-bottom: 8px; margin-bottom: 4px;
  }
  .ws-row { border-bottom: 1px solid var(--border); }
  .ws-row:last-child { border-bottom: none; }
  .num { font-weight: 600; color: var(--accent); }
  .small { padding: 4px 8px; font-size: 11px; }
  .empty { color: var(--text-muted); text-align: center; padding: 24px; }
  .add-card { padding: 14px 16px 4px; }
</style>
