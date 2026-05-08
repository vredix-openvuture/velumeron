<script lang="ts">
  import Monitors    from '$lib/sections/Monitors.svelte';
  import Workspaces  from '$lib/sections/Workspaces.svelte';
  import Peripherals from '$lib/sections/Peripherals.svelte';
  import Autostart   from '$lib/sections/Autostart.svelte';
  import QuickAccess from '$lib/sections/QuickAccess.svelte';
  import Variables   from '$lib/sections/Variables.svelte';
  import WindowRules from '$lib/sections/WindowRules.svelte';

  type Section = 'monitors' | 'workspaces' | 'peripherals' | 'autostart' | 'quickaccess' | 'variables' | 'windowrules';

  const NAV: { id: Section; label: string; icon: string }[] = [
    { id: 'monitors',    label: 'Monitore',      icon: '🖥' },
    { id: 'workspaces',  label: 'Workspaces',    icon: '⬜' },
    { id: 'peripherals', label: 'Peripherie',    icon: '🖱' },
    { id: 'autostart',   label: 'Autostart',     icon: '▶' },
    { id: 'quickaccess', label: 'Quick Access',  icon: '⚡' },
    { id: 'variables',   label: 'Variablen',     icon: '⚙' },
    { id: 'windowrules', label: 'Window Rules',  icon: '🪟' },
  ];

  let active = $state<Section>('monitors');
</script>

<div class="shell">
  <nav class="sidebar">
    <div class="logo">Vutureland</div>
    {#each NAV as item}
      <button
        class="nav-item {active === item.id ? 'active' : ''}"
        onclick={() => active = item.id}
      >
        <span class="nav-icon">{item.icon}</span>
        {item.label}
      </button>
    {/each}
  </nav>

  <main class="content">
    {#if active === 'monitors'}
      <Monitors />
    {:else if active === 'workspaces'}
      <Workspaces />
    {:else if active === 'peripherals'}
      <Peripherals />
    {:else if active === 'autostart'}
      <Autostart />
    {:else if active === 'quickaccess'}
      <QuickAccess />
    {:else if active === 'variables'}
      <Variables />
    {:else if active === 'windowrules'}
      <WindowRules />
    {/if}
  </main>
</div>

<style>
  .shell {
    display: flex;
    height: 100%;
    background: var(--bg);
    overflow: hidden;
  }

  .sidebar {
    width: 180px;
    flex-shrink: 0;
    background: var(--bg-panel);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    padding: 16px 10px;
    gap: 2px;
  }

  .logo {
    font-size: 14px;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.04em;
    padding: 0 8px 16px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 8px;
  }

  .nav-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 10px;
    border-radius: var(--radius-sm);
    background: transparent;
    border: none;
    color: var(--text-muted);
    font-size: 13px;
    text-align: left;
    cursor: pointer;
    transition: background 0.1s, color 0.1s;
    width: 100%;
  }
  .nav-item:hover { background: var(--bg-card); color: var(--text); }
  .nav-item.active { background: var(--bg-card); color: var(--text); border-left: 2px solid var(--accent); padding-left: 8px; }

  .nav-icon { font-size: 14px; width: 18px; text-align: center; }

  .content {
    flex: 1;
    overflow-y: auto;
    padding: 20px;
    min-width: 0;
  }
</style>
