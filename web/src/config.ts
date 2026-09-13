import { mainnet, sepolia, type Chain } from "viem/chains";
import type { Address } from "viem";
import type { ZkChain } from "./passport";

export interface Deployment {
  chain: Chain;
  zkChain: ZkChain;
  registry: Address | null;
  controller: Address | null;
  rpc: string;
  /** ZKPassport dev mode: accept mock passports. Testnets only. */
  devMode: boolean;
}

/**
 * The ZKPassport domain the PassportController was deployed with. Proofs are
 * scoped to it; a proof for another domain fails verification. Must match
 * PassportController.domain() on the target chain.
 */
export const ZK_DOMAIN = "donotresurrect.eth";

// Canonical deployment is mainnet. Others are mirrors; mainnet wins on conflict.
export const deployments: Deployment[] = [
  {
    chain: mainnet,
    zkChain: "ethereum",
    registry: null,
    controller: null,
    rpc: "https://ethereum-rpc.publicnode.com",
    devMode: false,
  },
  {
    chain: sepolia,
    zkChain: "ethereum_sepolia",
    registry: "0xD0782096437b6c2B668E64717556fE73f5C72eF4",
    controller: "0x47cF8D3281aF4d858F3fdf55662fD986274403A4",
    rpc: "https://ethereum-sepolia-rpc.publicnode.com",
    devMode: true,
  },
];

export const KIND_NAMES = ["NONE", "DO_NOT_RESURRECT", "RESURRECT_ONLY_IF", "RESURRECT"] as const;

export const KIND_DESCRIPTIONS = [
  "No directive on file.",
  "Do not reconstruct, emulate, simulate, or revive me in any form, from any substrate.",
  "Reconstruction is permitted only if the conditions in my document are met.",
  "Reconstruction is permitted. My document, if any, states preferences.",
] as const;
