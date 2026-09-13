import { defineConfig } from "vite";

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
});
