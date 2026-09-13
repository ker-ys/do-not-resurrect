// ZKPassport flow: build a request bound to this chain and to the hash of the
// exact action being authorised, show it as a QR / deep link, wait for the
// mobile app to return an EVM-verifiable proof, and format it for the
// PassportController contract.
import { ZKPassport, type ProofResult } from "@zkpassport/sdk";
import type { Hex } from "viem";

export const ZK_SCOPE = "dnr"; // must match PassportController.SCOPE

export type ZkChain =
  | "ethereum"
  | "ethereum_sepolia"
  | "base"
  | "base_sepolia"
  | "arbitrum"
  | "optimism"
  | "polygon"
  | "local";

export interface PassportRequest {
  url: string;
  requestId: string;
  /** Resolves with the outer EVM proof once the app has generated it. */
  proof: Promise<ProofResult>;
  onStatus: (cb: (status: string) => void) => void;
  zk: ZKPassport;
}

export async function requestPassportProof(opts: {
  domain: string;
  chain: ZkChain;
  devMode: boolean;
  /** Lowercase 0x-prefixed keccak256 from PassportController.declareBinding / rotateBinding. */
  binding: Hex;
  purpose: string;
}): Promise<PassportRequest> {
  const zk = new ZKPassport(opts.domain);
  const builder = await zk.request({
    name: "Do Not Resurrect",
    purpose: opts.purpose,
    scope: ZK_SCOPE,
    mode: "compressed-evm",
    devMode: opts.devMode,
  });

  const { url, requestId, onRequestReceived, onGeneratingProof, onProofGenerated, onResult, onReject, onError } =
    builder.bind("chain", opts.chain).bind("custom_data", opts.binding.toLowerCase()).done();

  const statusCbs: ((s: string) => void)[] = [];
  const emit = (s: string) => statusCbs.forEach((cb) => cb(s));

  const proof = new Promise<ProofResult>((resolve, reject) => {
    onRequestReceived(() => emit("Request received by the app."));
    onGeneratingProof(() => emit("Generating proof on the phone. This takes a little while."));
    onProofGenerated((p) => {
      emit(`Proof generated (${p.name ?? "unnamed"}).`);
      if (p.name?.startsWith("outer_evm")) resolve(p);
    });
    onResult(({ proofs }) => {
      const evm = proofs.find((p: ProofResult) => p.name?.startsWith("outer_evm"));
      if (evm) resolve(evm);
      else reject(new Error("No EVM-verifiable proof returned. Is the request in compressed-evm mode?"));
    });
    onReject(() => reject(new Error("Rejected in the app.")));
    onError((e: string) => reject(new Error(e || "ZKPassport error")));
  });

  return { url, requestId, proof, onStatus: (cb) => statusCbs.push(cb), zk };
}

/** Format an outer EVM proof as the ProofVerificationParams struct the contract expects. */
export function toVerifierParams(zk: ZKPassport, proof: ProofResult, domain: string, devMode: boolean) {
  const p = zk.getSolidityVerifierParameters({ proof, domain, scope: ZK_SCOPE, devMode });
  return {
    version: p.version as Hex,
    proofVerificationData: {
      vkeyHash: p.proofVerificationData.vkeyHash as Hex,
      proof: p.proofVerificationData.proof as Hex,
      publicInputs: p.proofVerificationData.publicInputs as Hex[],
    },
    committedInputs: p.committedInputs as Hex,
    serviceConfig: {
      validityPeriodInSeconds: BigInt(p.serviceConfig.validityPeriodInSeconds),
      domain: p.serviceConfig.domain,
      scope: p.serviceConfig.scope,
      devMode: p.serviceConfig.devMode,
    },
  } as const;
}
