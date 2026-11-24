<script lang="ts">
  import { onMount, tick } from "svelte";
  import { picker, type PickerInput, type PickerView } from "../lib/api";
  import { t } from "../lib/i18n";
  import TargetIcon from "../lib/TargetIcon.svelte";

  let view = $state<PickerView | null>(null);
  let root = $state<HTMLElement>();
  let list = $state<HTMLElement>();

  async function send(input: PickerInput) {
    const next = await picker.input(input);
    if (next) view = next;
  }

  async function show(next: PickerView | null) {
    view = next;
    await tick();
    if (root) picker.resize(Math.ceil(root.getBoundingClientRect().height));
    list?.querySelector<HTMLElement>('[aria-selected="true"]')?.scrollIntoView({ block: "nearest" });
  }

  function onKey(e: KeyboardEvent) {
    if (!view) return;
    if (e.key === "Tab" || e.key.startsWith("Arrow") || e.key === "Enter" || e.key === "Home" || e.key === "End") {
      e.preventDefault();
    }
    if (e.repeat && e.key.length === 1) return;
    send({ type: "key", key: e.key, ctrl: e.ctrlKey, alt: e.altKey, shift: e.shiftKey, meta: e.metaKey });
  }

  $effect(() => {
    if (view && list) {
      list.querySelector<HTMLElement>('[aria-selected="true"]')?.scrollIntoView({ block: "nearest" });
    }
  });

  onMount(() => {
    picker.state().then(show);
    const off = picker.onState((v) => show(v));
    window.addEventListener("keydown", onKey);
    window.addEventListener("contextmenu", (e) => e.preventDefault());
    return () => {
      off.then((f) => f());
      window.removeEventListener("keydown", onKey);
    };
  });

  const link = $derived(view && view.links.length === 1 ? view.links[0] : null);
</script>

{#if view}
  <main bind:this={root} style:--accent={view.accent}>
    <header title={view.links.map((l) => l.line).join("\n")}>
      {#if link}
        <span class="host">{link.primary}</span><span class="rest">{link.secondary}</span>
      {:else}
        <span class="host">{t("{n} links", { n: view.links.length })}</span>
      {/if}
    </header>

    {#if view.configUnreadable}
      <p class="notice">{t("The configuration file can't be read; defaults are in use.")}</p>
    {/if}

    {#if view.entries.length === 0}
      <div class="empty">
        <p>{t("No visible targets")}</p>
        <button onclick={() => send({ type: "settingsButton" })}>{t("Settings…")}</button>
      </div>
    {:else}
      <ul role="listbox" aria-label="Browserdoor" bind:this={list}>
        {#each view.entries as entry, i (entry.id)}
          <!-- Keys are handled for the whole window (onKey), like a menu. -->
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <li
            role="option"
            aria-selected={i === view.selection}
            aria-label={entry.label}
            aria-keyshortcuts={entry.hotkey ?? undefined}
            class:selected={i === view.selection}
            onclick={() => send({ type: "click", row: i })}
            onmousemove={(e) => send({ type: "hover", row: i, x: e.screenX, y: e.screenY })}
          >
            <TargetIcon icon={entry.icon} />
            <span class="label">{entry.label}</span>
            {#if i === view.defaultRow}<span class="return" title={t("Default target")}>↩</span>{/if}
            {#if entry.hotkey}<span class="keycap">{entry.hotkey.toUpperCase()}</span>{/if}
          </li>
        {/each}
      </ul>
    {/if}

    <footer>
      <button class="subtle" onclick={() => send({ type: "copyButton" })}>
        {view.copied ? `✓ ${t("Copied")}` : t("Copy URL")}
      </button>
      <span class="hint">Ctrl+C</span>
    </footer>
  </main>
{/if}

<style>
  main {
    display: flex;
    flex-direction: column;
    max-height: 100vh;
    padding: 4px 0;
  }

  header {
    padding: 10px 14px 9px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: flex;
    min-width: 0;
  }

  .host {
    font-weight: 600;
    flex: none;
    max-width: 75%;
    overflow: hidden;
    text-overflow: ellipsis;
    direction: rtl;
    text-align: left;
  }

  .rest {
    color: var(--text-2);
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
  }

  .notice {
    margin: 0 10px 6px;
    padding: 6px 10px;
    border-radius: 4px;
    background: rgb(252 225 0 / 0.18);
    font-size: 12px;
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 2px 4px;
    overflow-y: auto;
    border-top: 1px solid var(--divider);
    border-bottom: 1px solid var(--divider);
  }

  li {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 36px;
    padding: 0 8px 0 12px;
    margin: 2px 0;
    border-radius: 4px;
  }

  li.selected {
    background: var(--selected);
  }

  li.selected::before {
    content: "";
    position: absolute;
    left: 0;
    top: 10px;
    bottom: 10px;
    width: 3px;
    border-radius: 2px;
    background: var(--accent);
  }

  .label {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .return {
    color: var(--text-3);
    font-size: 13px;
  }

  .empty {
    padding: 16px 14px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    border-top: 1px solid var(--divider);
    border-bottom: 1px solid var(--divider);
  }

  .empty p {
    margin: 0;
    color: var(--text-2);
  }

  footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 4px 8px 0;
  }

  .hint {
    color: var(--text-3);
    font-size: 12px;
    padding-right: 6px;
  }
</style>
