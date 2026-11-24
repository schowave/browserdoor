<script lang="ts">
  import { onMount, tick } from "svelte";
  import { settings, type SettingsView, type TargetRowView } from "../lib/api";
  import { t } from "../lib/i18n";
  import TargetIcon from "../lib/TargetIcon.svelte";

  type Tab = "general" | "targets" | "advanced";

  let view = $state<SettingsView | null>(null);
  const tabs: Tab[] = ["general", "targets", "advanced"];
  const fromHash = location.hash.slice(1) as Tab;
  let tab = $state<Tab>(tabs.includes(fromHash) ? fromHash : "general");
  let recording = $state<string | null>(null);
  let renaming = $state<string | null>(null);
  let renameText = $state("");
  let notice = $state<string | null>(null);
  let noticeTimer: number | undefined;
  let menu = $state<{ row: TargetRowView; x: number; y: number } | null>(null);
  let dragFrom = $state<number | null>(null);
  let dropAt = $state<number | null>(null);

  async function run(p: Promise<SettingsView>) {
    try {
      view = await p;
    } catch (e) {
      console.error(e);
    }
  }

  function showNotice(text: string) {
    notice = text;
    clearTimeout(noticeTimer);
    noticeTimer = window.setTimeout(() => (notice = null), 4000);
  }

  // The key field is a recorder: click it, press a key. Esc cancels, Delete or Backspace removes
  // the custom key (SPEC 6.3).
  function onRecorderKey(e: KeyboardEvent, row: TargetRowView) {
    e.preventDefault();
    e.stopPropagation();
    if (e.key === "Escape") {
      recording = null;
      return;
    }
    if (e.key === "Delete" || e.key === "Backspace") {
      recording = null;
      settings.setHotkey(row.id, "").then((r) => (view = r.view));
      return;
    }
    if (e.key.length !== 1 || e.ctrlKey || e.metaKey || (e.altKey && !e.ctrlKey) || e.key === " ") return;
    recording = null;
    settings.setHotkey(row.id, e.key).then((r) => {
      view = r.view;
      if (r.previous) showNotice(t("{key} moved here from {name}.", { key: e.key.toUpperCase(), name: r.previous }));
    });
  }

  async function startRename(row: TargetRowView) {
    renaming = row.id;
    renameText = row.displayName;
    await tick();
    document.querySelector<HTMLInputElement>("input.rename")?.select();
  }

  function commitRename(row: TargetRowView) {
    if (renaming !== row.id) return;
    renaming = null;
    if (renameText !== row.displayName) run(settings.rename(row.id, renameText.trim()));
  }

  function onDrop(to: number) {
    if (dragFrom !== null && view) {
      const target = to > dragFrom ? to - 1 : to;
      if (target !== dragFrom) run(settings.moveRow(dragFrom, target));
    }
    dragFrom = null;
    dropAt = null;
  }

  function onRowKey(e: KeyboardEvent, index: number) {
    if (!view) return;
    if (e.altKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
      e.preventDefault();
      const to = e.key === "ArrowUp" ? index - 1 : index + 1;
      if (to >= 0 && to < view.rows.length) run(settings.moveRow(index, to));
    }
  }

  function updateLine(v: SettingsView): string {
    switch (v.update.kind) {
      case "checking":
        return t("Checking…");
      case "upToDate":
        return t("Browserdoor {v} is up to date.", { v: v.version });
      case "available":
        return t("Browserdoor {v} is available.", { v: v.update.version });
      case "failed":
        return v.update.message;
      default:
        return t("Version {v}", { v: v.version });
    }
  }

  onMount(() => {
    settings.state().then((v) => (view = v));
    const offs = [
      settings.onChanged(() => settings.state().then((v) => (view = v))),
      settings.onShowTab((name) => (tab = name as Tab)),
    ];
    const closeMenu = () => (menu = null);
    window.addEventListener("click", closeMenu);
    window.addEventListener("blur", closeMenu);
    const noBrowserMenu = (e: Event) => e.preventDefault();
    window.addEventListener("contextmenu", noBrowserMenu);
    return () => {
      offs.forEach((o) => o.then((f) => f()));
      window.removeEventListener("click", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("contextmenu", noBrowserMenu);
    };
  });
</script>

{#if view}
  <div class="window" style:--accent={view.accent}>
    <div class="tabs" role="tablist" aria-label="Browserdoor">
      {#each [["general", t("General")], ["targets", t("Targets")], ["advanced", t("Advanced")]] as [id, label] (id)}
        <button
          role="tab"
          class="subtle tab"
          aria-selected={tab === id}
          class:active={tab === id}
          onclick={() => (tab = id as Tab)}>{label}</button
        >
      {/each}
    </div>

    {#if tab === "general"}
      <section class="pane">
        <div class="card">
          <div class="text">
            <h2>{t("Default browser")}</h2>
            <p>
              {view.isDefaultBrowser
                ? t("Browserdoor is your default browser.")
                : t("Browserdoor is not your default browser.")}
            </p>
            {#if !view.isDefaultBrowser}
              <p class="secondary">{t("Windows asks you to choose Browserdoor in Settings › Apps › Default apps.")}</p>
            {/if}
          </div>
          {#if !view.isDefaultBrowser}
            <button class="accent" onclick={() => settings.makeDefault()}>{t("Make Default Browser…")}</button>
          {/if}
        </div>

        <label class="card">
          <div class="text">
            <h2>{t("Start at login")}</h2>
            {#if view.autostartError}<p class="error">{view.autostartError}</p>{/if}
          </div>
          <input
            type="checkbox"
            class="toggle"
            checked={view.autostart}
            onchange={(e) => run(settings.setAutostart(e.currentTarget.checked))}
          />
        </label>

        <label class="card">
          <div class="text">
            <h2>{t("Show in notification area")}</h2>
            <p class="secondary">{t("Without the icon, start Browserdoor again to open the settings.")}</p>
          </div>
          <input
            type="checkbox"
            class="toggle"
            checked={view.showInTray}
            onchange={(e) => run(settings.setShowInTray(e.currentTarget.checked))}
          />
        </label>

        <div class="card column">
          <div class="row">
            <div class="text">
              <h2>{t("Updates")}</h2>
              <p class:error={view.update.kind === "failed"}>{updateLine(view)}</p>
            </div>
            {#if view.update.kind === "available"}
              <button class="accent" onclick={() => settings.update()}>{t("Update…")}</button>
            {:else}
              <button disabled={view.update.kind === "checking"} onclick={() => run(settings.checkForUpdates())}>
                {t("Check Now")}
              </button>
            {/if}
          </div>
          <label class="row inner">
            <span>{t("Check for updates automatically")}</span>
            <input
              type="checkbox"
              class="toggle"
              checked={view.checkAutomatically}
              onchange={(e) => run(settings.setCheckAutomatically(e.currentTarget.checked))}
            />
          </label>
        </div>
      </section>
    {:else if tab === "targets"}
      <section class="pane targets">
        <div class="list" role="list">
          {#each view.rows as row, i (row.id)}
            <!-- Sorting by keyboard: Alt+↑/↓ (onRowKey). -->
            <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
            <div
              role="listitem"
              class="target"
              class:hidden={row.hidden}
              class:drop-before={dropAt === i && dragFrom !== null && dragFrom !== i && dragFrom !== i - 1}
              draggable={recording === null && renaming === null}
              ondragstart={(e) => {
                dragFrom = i;
                e.dataTransfer?.setData("text/plain", row.id);
              }}
              ondragover={(e) => {
                e.preventDefault();
                const r = e.currentTarget.getBoundingClientRect();
                dropAt = e.clientY < r.top + r.height / 2 ? i : i + 1;
              }}
              ondrop={(e) => {
                e.preventDefault();
                onDrop(dropAt ?? i);
              }}
              ondragend={() => {
                dragFrom = null;
                dropAt = null;
              }}
              oncontextmenu={(e) => {
                e.preventDefault();
                menu = { row, x: e.clientX, y: e.clientY };
              }}
              onkeydown={(e) => onRowKey(e, i)}
            >
              <span class="handle" aria-hidden="true">⋮⋮</span>
              <input
                type="checkbox"
                checked={!row.hidden}
                aria-label={`${t("Show")}: ${row.displayName}`}
                onchange={(e) => run(settings.setHidden(row.id, !e.currentTarget.checked))}
              />
              <TargetIcon icon={row.icon} />
              {#if renaming === row.id}
                <input
                  type="text"
                  class="rename"
                  aria-label={t("Name")}
                  bind:value={renameText}
                  placeholder={row.name}
                  onblur={() => commitRename(row)}
                  onkeydown={(e) => {
                    if (e.key === "Enter") commitRename(row);
                    if (e.key === "Escape") renaming = null;
                  }}
                />
              {:else}
                <span class="name" role="button" tabindex="0" title={row.name} ondblclick={() => startRename(row)}
                  onkeydown={(e) => e.key === "F2" && startRename(row)}>{row.displayName}</span
                >
              {/if}
              <button
                class="recorder keycap"
                class:custom={row.hotkey !== null}
                class:recording={recording === row.id}
                aria-label={`${t("Key")}: ${row.effectiveKey ?? "—"}`}
                onclick={(e) => {
                  e.stopPropagation();
                  recording = recording === row.id ? null : row.id;
                }}
                onkeydown={(e) => recording === row.id && onRecorderKey(e, row)}
                onblur={() => recording === row.id && (recording = null)}
              >
                {recording === row.id ? t("Press a key") : (row.effectiveKey?.toUpperCase() ?? "—")}
              </button>
              <button
                class="subtle star"
                class:on={row.isDefault}
                aria-label={t("Default target")}
                aria-pressed={row.isDefault}
                onclick={() => run(settings.toggleDefault(row.id))}>{row.isDefault ? "★" : "☆"}</button
              >
            </div>
          {/each}
          <div
            class="drop-end"
            class:drop-before={dropAt === view.rows.length && dragFrom !== null && dragFrom !== view.rows.length - 1}
            role="presentation"
            ondragover={(e) => {
              e.preventDefault();
              dropAt = view!.rows.length;
            }}
            ondrop={(e) => {
              e.preventDefault();
              onDrop(view!.rows.length);
            }}
          ></div>
        </div>

        {#if notice}<p class="notice" role="status">{notice}</p>{/if}

        {#if view.unlistedExtraApps.length > 0}
          <div class="unlisted">
            <p class="secondary">{t("Added apps that aren't listed:")}</p>
            {#each view.unlistedExtraApps as app (app.exe)}
              <div class="row">
                <span title={app.exe}>{app.name}</span>
                <button class="subtle" onclick={() => run(settings.removeExtraApp(app.exe))}>{t("Remove")}</button>
              </div>
            {/each}
          </div>
        {/if}

        <div class="bar">
          <button onclick={() => run(settings.addExtraApp())}>{t("Add App…")}</button>
          <span class="secondary">{t("Drag to sort. Esc cancels a key, Delete removes it.")}</span>
        </div>
      </section>
    {:else}
      <section class="pane">
        <div class="card column">
          <h2>{t("Zen profile")}</h2>
          <p class="path">{view.zenProfilePath ?? t("Zen's default profile")}</p>
          <div class="row start">
            <button onclick={() => run(settings.pickZenProfile())}>{t("Choose Folder…")}</button>
            {#if view.zenProfilePath}
              <button onclick={() => run(settings.setZenProfile(null))}>{t("Use Default")}</button>
            {/if}
          </div>
        </div>
        <div class="card column">
          <h2>{t("Configuration file")}</h2>
          <p class="path">{view.configPath}</p>
          {#if view.configUnreadable}
            <p class="error">{t("The configuration file can't be read; defaults are in use.")}</p>
          {/if}
          <div class="row start">
            <button onclick={() => settings.revealConfig()}>{t("Show in Explorer")}</button>
          </div>
        </div>
      </section>
    {/if}

    {#if menu}
      {@const row = menu.row}
      <div class="menu" role="menu" style:left="{menu.x}px" style:top="{menu.y}px">
        <button role="menuitem" class="subtle" onclick={() => startRename(row)}>{t("Rename")}</button>
        <button role="menuitem" class="subtle" onclick={() => run(settings.toggleDefault(row.id))}>
          {row.isDefault ? t("Remove as Default Target") : t("Make Default Target")}
        </button>
        <button role="menuitem" class="subtle" onclick={() => run(settings.setHidden(row.id, !row.hidden))}>
          {row.hidden ? t("Show in Picker") : t("Hide in Picker")}
        </button>
        {#if row.extraApp}
          <button role="menuitem" class="subtle" onclick={() => run(settings.removeExtraApp(row.extraApp!))}>
            {t("Remove App")}
          </button>
        {/if}
      </div>
    {/if}
  </div>
{/if}

<style>
  .window {
    height: 100vh;
    display: flex;
    flex-direction: column;
  }

  .tabs {
    display: flex;
    gap: 4px;
    padding: 10px 16px 6px;
  }

  .tab {
    position: relative;
    padding: 6px 12px;
    color: var(--text-2);
  }

  .tab.active {
    color: var(--text);
    font-weight: 600;
  }

  .tab.active::after {
    content: "";
    position: absolute;
    left: 50%;
    bottom: 2px;
    width: 16px;
    height: 3px;
    margin-left: -8px;
    border-radius: 2px;
    background: var(--accent);
  }

  .pane {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 8px 16px 16px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .card {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 14px 16px;
    border-radius: 6px;
    background: var(--card);
    border: 1px solid var(--card-border);
  }

  .card.column {
    flex-direction: column;
    align-items: stretch;
    gap: 8px;
  }

  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .row.start {
    justify-content: flex-start;
  }

  .row.inner {
    padding-top: 8px;
    border-top: 1px solid var(--divider);
  }

  h2 {
    margin: 0;
    font-size: 14px;
    font-weight: 400;
  }

  p {
    margin: 2px 0 0;
    font-size: 12px;
    color: var(--text-2);
  }

  .secondary {
    font-size: 12px;
    color: var(--text-2);
  }

  .error {
    color: #c42b1c;
  }

  .path {
    font-family: "Cascadia Mono", Consolas, monospace;
    word-break: break-all;
    user-select: text;
    -webkit-user-select: text;
  }

  .toggle {
    appearance: none;
    width: 40px;
    height: 20px;
    border-radius: 10px;
    border: 1px solid var(--text-2);
    position: relative;
    flex: none;
    transition: background 0.1s;
  }

  .toggle::after {
    content: "";
    position: absolute;
    top: 3px;
    left: 3px;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--text-2);
    transition: transform 0.1s;
  }

  .toggle:checked {
    background: var(--accent);
    border-color: var(--accent);
  }

  .toggle:checked::after {
    transform: translateX(20px);
    background: #fff;
  }

  .targets {
    gap: 8px;
  }

  .list {
    border-radius: 6px;
    background: var(--card);
    border: 1px solid var(--card-border);
    padding: 4px;
  }

  .target {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 40px;
    padding: 0 6px;
    border-radius: 4px;
    border-top: 2px solid transparent;
  }

  .target:hover {
    background: var(--subtle-hover);
  }

  .target.hidden .name {
    color: var(--text-3);
  }

  .drop-before {
    border-top-color: var(--accent);
  }

  .drop-end {
    height: 6px;
    border-top: 2px solid transparent;
  }

  .handle {
    color: var(--text-3);
    letter-spacing: -3px;
    cursor: grab;
    width: 12px;
  }

  .name {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rename {
    flex: 1;
    min-height: 28px;
    padding: 2px 8px;
  }

  .recorder {
    border: 1px solid transparent;
    min-height: 26px;
    height: 26px;
    min-width: 34px;
    padding: 0 8px;
    color: var(--text-3);
  }

  .recorder.custom {
    color: var(--text);
  }

  .recorder.recording {
    border-color: var(--accent);
    color: var(--accent);
  }

  .star {
    min-height: 28px;
    width: 32px;
    padding: 0;
    color: var(--text-3);
    font-size: 16px;
  }

  .star.on {
    color: #e0a800;
  }

  .notice {
    padding: 6px 10px;
    border-radius: 4px;
    background: var(--card);
    color: var(--text);
  }

  .unlisted {
    padding: 8px 12px;
    border-radius: 6px;
    background: var(--card);
  }

  .bar {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .menu {
    position: fixed;
    z-index: 10;
    display: flex;
    flex-direction: column;
    min-width: 200px;
    padding: 4px;
    border-radius: 8px;
    background: var(--fallback-bg);
    border: 1px solid var(--divider);
    box-shadow: 0 8px 16px rgb(0 0 0 / 0.14);
  }

  .menu button {
    text-align: left;
    min-height: 30px;
  }
</style>
