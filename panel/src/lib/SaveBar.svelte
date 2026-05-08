<script lang="ts">
  interface Props {
    onSave: () => Promise<void>;
    onReload?: () => Promise<void>;
  }
  let { onSave, onReload }: Props = $props();

  let status = $state<'idle' | 'saving' | 'ok' | 'err'>('idle');
  let msg = $state('');

  async function save() {
    status = 'saving';
    try {
      await onSave();
      status = 'ok';
      msg = 'Gespeichert';
    } catch (e) {
      status = 'err';
      msg = String(e);
    }
    setTimeout(() => { status = 'idle'; }, 2500);
  }

  async function reload() {
    if (!onReload) return;
    status = 'saving';
    try {
      await onSave();
      await onReload();
      status = 'ok';
      msg = 'Gespeichert & neu geladen';
    } catch (e) {
      status = 'err';
      msg = String(e);
    }
    setTimeout(() => { status = 'idle'; }, 2500);
  }
</script>

<div class="save-bar">
  {#if status === 'ok'}
    <span class="status ok">{msg}</span>
  {:else if status === 'err'}
    <span class="status err">{msg}</span>
  {/if}
  {#if onReload}
    <button class="btn-ghost" onclick={reload} disabled={status === 'saving'}>
      Speichern & Reload
    </button>
  {/if}
  <button class="btn-primary" onclick={save} disabled={status === 'saving'}>
    {status === 'saving' ? 'Speichern…' : 'Speichern'}
  </button>
</div>
