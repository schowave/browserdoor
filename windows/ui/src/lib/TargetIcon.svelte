<script lang="ts">
  import { css, onColor, type TargetIconView } from "./api";

  let { icon, size = 20 }: { icon: TargetIconView; size?: number } = $props();
</script>

<span class="icon" style:width="{size}px" style:height="{size}px" aria-hidden="true">
  {#if icon.image}
    <img src={icon.image} alt="" width={size} height={size} />
  {:else}
    <span
      class="glyph"
      style:background={icon.color ? css(icon.color) : "var(--accent)"}
      style:color={icon.color ? onColor(icon.color) : "#fff"}
      style:font-size="{icon.emoji ? size * 0.62 : size * 0.5}px"
    >
      {icon.emoji ?? icon.initial ?? "?"}
    </span>
  {/if}
  {#if icon.badge}
    <span class="badge" style:background={css(icon.badge.color)}>{icon.badge.letter}</span>
  {/if}
</span>

<style>
  .icon {
    position: relative;
    display: inline-block;
    flex: none;
  }

  img {
    display: block;
  }

  .glyph {
    width: 100%;
    height: 100%;
    border-radius: 5px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
    line-height: 1;
  }

  .badge {
    position: absolute;
    right: -4px;
    bottom: -3px;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    color: #fff;
    font-size: 8px;
    font-weight: 700;
    line-height: 12px;
    text-align: center;
    box-shadow: 0 0 0 1.5px var(--fallback-bg);
  }
</style>
