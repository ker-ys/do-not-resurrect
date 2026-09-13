import { mainnet, sepolia, type Chain } from "viem/chains";
import type { Address } from "viem";

export interface Deployment {
  chain: Chain;
  registry: Address | null;
  rpc: string;
}

// Canonical deployment is mainnet. Others are mirrors; mainnet wins on conflict.
export const deployments: Deployment[] = [
  { chain: mainnet, registry: null, rpc: "https://ethereum-rpc.publicnode.com" },
  { chain: sepolia, registry: null, rpc: "https://ethereum-sepolia-rpc.publicnode.com" },
];

export const KIND_NAMES = ["NONE", "DO_NOT_RESURRECT", "RESURRECT_ONLY_IF", "RESURRECT"] as const;

export const KIND_DESCRIPTIONS = [
  "No directive on file.",
  "Do not reconstruct, emulate, simulate, or revive me in any form, from any substrate.",
  "Reconstruction is permitted only if the conditions in my document are met.",
  "Reconstruction is permitted. My document, if any, states preferences.",
] as const;
