import { svelte } from "@sveltejs/vite-plugin-svelte";
import { resolve } from "node:path";
import { defineConfig } from "vite";

// Two pages, one per window: the picker and the settings.
export default defineConfig({
  plugins: [svelte()],
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: {
    target: "chrome120",
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        picker: resolve(import.meta.dirname, "picker.html"),
        settings: resolve(import.meta.dirname, "settings.html"),
      },
    },
  },
});
