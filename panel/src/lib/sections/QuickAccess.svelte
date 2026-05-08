<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke } from '$lib/invoke';
  import SaveBar from '$lib/SaveBar.svelte';

  let apps = $state<string[]>(Array(10).fill(''));

  onMount(async () => {
    apps = await invoke<string[]>('read_quickaccess_conf');
  });

  async function onSave() {
    await invoke('write_quickaccess_conf', { apps });
  }
</script>

<div class="page">
  <div class="card">
    <p class="section-title">Quick Access Apps (Super+Q, dann 1–9)</p>
    <div class="qa-list">
      {#each apps as _, i}
        <div class="qa-row">
          <span class="qa-num">{i + 1}</span>
          <input bind:value={apps[i]} placeholder="(leer = deaktiviert)" />
        </div>
      {/each}
    </div>
  </div>
  <SaveBar {onSave} />
</div>

<style>
  .page { display: flex; flex-direction: column; gap: 12px; }
  .qa-list { display: flex; flex-direction: column; gap: 6px; }
  .qa-row { display: flex; gap: 10px; align-items: center; }
  .qa-num {
    width: 28px; height: 28px; border-radius: 6px;
    background: var(--accent); color: #fff;
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 700; flex-shrink: 0;
  }
</style>
