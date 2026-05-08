<script lang="ts">
  interface Props {
    checked: boolean;
    onchange?: (val: boolean) => void;
  }
  let { checked = $bindable(), onchange }: Props = $props();
</script>

<label class="toggle">
  <input
    type="checkbox"
    bind:checked
    onchange={() => onchange?.(checked)}
  />
  <span class="slider"></span>
</label>
