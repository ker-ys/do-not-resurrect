import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

// Relative base so the build works from any IPFS gateway path
// (ipfs://<cid>/ or https://gateway/ipfs/<cid>/).
export default defineConfig({
  base: "./",
  build: {
    target: "es2022",
    outDir: "dist",
    assetsInlineLimit: 0,
    sourcemap: false,
  },
  plugins: [
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["icon.svg"],
      manifest: {
        name: "Do Not Resurrect",
        short_name: "DNR",
        description: "Control your connectome. An onchain registry of posthumous directives.",
        start_url: "./",
        scope: "./",
        display: "standalone",
        background_color: "#0b0c0e",
        theme_color: "#0b0c0e",
        icons: [{ src: "icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" }],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg}"],
        // barretenberg (local ZK verifier) is lazy-loaded by the SDK and never needed here
        globIgnores: ["**/barretenberg*"],
        // proof artifacts and RPC are network-only; only the shell is cached
        navigateFallback: null,
        maximumFileSizeToCacheInBytes: 8 * 1024 * 1024,
      },
    }),
  ],
});
