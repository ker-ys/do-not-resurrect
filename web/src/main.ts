import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  isAddress,
  isHex,
  keccak256,
  stringToBytes,
  concat,
  encodeAbiParameters,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from "viem";
import { registryAbi } from "./abi";
import { deployments, KIND_DESCRIPTIONS, KIND_NAMES, type Deployment } from "./config";

declare global {
  interface Window {
    ethereum?: any;
  }
}

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

const els = {
  net: $("net"),
  connect: $<HTMLButtonElement>("connect"),
  scheme: $<HTMLSelectElement>("scheme"),
  fp: $<HTMLTextAreaElement>("fp"),
  subject: $("subject"),
  lookup: $<HTMLButtonElement>("lookup"),
  record: $<HTMLPreElement>("record"),
  kind: $<HTMLSelectElement>("kind"),
  kindDesc: $("kindDesc"),
  doc: $<HTMLTextAreaElement>("doc"),
  uri: $<HTMLInputElement>("uri"),
  docHash: $("docHash"),
  commit: $<HTMLButtonElement>("commit"),
  declare: $<HTMLButtonElement>("declare"),
  log: $<HTMLPreElement>("log"),
  newController: $<HTMLInputElement>("newController"),
  rotate: $<HTMLButtonElement>("rotate"),
};

const ZERO32 = `0x${"0".repeat(64)}` as Hex;

let deployment: Deployment | null = null;
let publicClient: PublicClient | null = null;
let walletClient: WalletClient | null = null;
let account: Address | null = null;

// ---------------------------------------------------------------------
// Derivations
// ---------------------------------------------------------------------

function subject(): Hex | null {
  const v = els.fp.value.trim();
  if (!v) return null;
  if (els.scheme.value === "raw") {
    return isHex(v) && v.length === 66 ? (v as Hex) : null;
  }
  return keccak256(concat([stringToBytes("dnr:g1:"), stringToBytes(v)]));
}

function conditionsHash(): Hex {
  const d = els.doc.value;
  return d.length ? keccak256(stringToBytes(d)) : ZERO32;
}

function commitmentFor(s: Hex, controller: Address): Hex {
  return keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "address" }], [s, controller]));
}

// ---------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------

function log(msg: string) {
  els.log.textContent += (els.log.textContent ? "\n" : "") + msg;
  els.log.scrollTop = els.log.scrollHeight;
}

function refresh() {
  const s = subject();
  els.subject.textContent = `subject: ${s ?? "—"}`;
  els.docHash.textContent = `conditionsHash: ${conditionsHash()}`;
  els.kindDesc.textContent = KIND_DESCRIPTIONS[Number(els.kind.value)];
  const ready = !!s && !!deployment?.registry;
  els.lookup.disabled = !ready;
  els.commit.disabled = !ready || !account;
  els.declare.disabled = !ready || !account;
  els.rotate.disabled = !ready || !account || !isAddress(els.newController.value.trim());
}

function describeNet() {
  if (!deployment) {
    els.net.textContent = "No wallet connected.";
    return;
  }
  const addr = deployment.registry ?? "not deployed on this chain";
  els.net.textContent = `${deployment.chain.name} · registry ${addr}` + (account ? ` · ${account}` : "");
}

// ---------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------

async function connect() {
  if (!window.ethereum) {
    log("No injected wallet found.");
    return;
  }
  const [addr] = (await window.ethereum.request({ method: "eth_requestAccounts" })) as Address[];
  const chainIdHex = (await window.ethereum.request({ method: "eth_chainId" })) as Hex;
  const chainId = Number(chainIdHex);
  deployment = deployments.find((d) => d.chain.id === chainId) ?? null;
  if (!deployment) {
    els.net.textContent = `Chain ${chainId} is not supported. Switch to ${deployments.map((d) => d.chain.name).join(" or ")}.`;
    return;
  }
  account = addr;
  publicClient = createPublicClient({ chain: deployment.chain, transport: http(deployment.rpc) });
  walletClient = createWalletClient({ chain: deployment.chain, transport: custom(window.ethereum), account });
  describeNet();
  refresh();
  window.ethereum.on?.("chainChanged", () => location.reload());
  window.ethereum.on?.("accountsChanged", () => location.reload());
}

// ---------------------------------------------------------------------
// Chain reads/writes
// ---------------------------------------------------------------------

async function lookup() {
  const s = subject();
  if (!s || !publicClient || !deployment?.registry) return;
  const r = await publicClient.readContract({
    address: deployment.registry,
    abi: registryAbi,
    functionName: "getRecord",
    args: [s],
  });
  els.record.hidden = false;
  if (r.controller === "0x0000000000000000000000000000000000000000") {
    els.record.textContent = "No record. Subject is unclaimed.";
    return;
  }
  els.record.textContent = [
    `controller:     ${r.controller}`,
    `kind:           ${r.kind} ${KIND_NAMES[r.kind] ?? "(unknown)"}`,
    `conditionsHash: ${r.conditionsHash}`,
    `uri:            ${r.uri || "—"}`,
    `nonce:          ${r.nonce}`,
    `block:          ${r.blockNumber}`,
  ].join("\n");
}

async function currentNonce(s: Hex): Promise<bigint> {
  const n = await publicClient!.readContract({
    address: deployment!.registry!,
    abi: registryAbi,
    functionName: "nonceOf",
    args: [s],
  });
  return BigInt(n);
}

async function send(fn: "commit" | "declare" | "rotate", args: readonly unknown[]) {
  if (!walletClient || !publicClient || !deployment?.registry || !account) return;
  try {
    const { request } = await publicClient.simulateContract({
      address: deployment.registry,
      abi: registryAbi,
      functionName: fn,
      args: args as any,
      account,
    });
    const hash = await walletClient.writeContract(request);
    log(`${fn}: sent ${hash}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    log(`${fn}: ${receipt.status} in block ${receipt.blockNumber}`);
    await lookup();
  } catch (e: any) {
    log(`${fn}: ${e.shortMessage ?? e.message ?? String(e)}`);
  }
}

async function commit() {
  const s = subject();
  if (!s || !account) return;
  await send("commit", [commitmentFor(s, account)]);
  log("Now wait one block, then Declare.");
}

async function declare() {
  const s = subject();
  if (!s) return;
  const nonce = await currentNonce(s);
  await send("declare", [
    {
      subject: s,
      kind: Number(els.kind.value),
      conditionsHash: conditionsHash(),
      uri: els.uri.value.trim(),
      nonce,
    },
  ]);
}

async function rotate() {
  const s = subject();
  const to = els.newController.value.trim();
  if (!s || !isAddress(to)) return;
  await send("rotate", [s, to]);
}

// ---------------------------------------------------------------------
// Wire up
// ---------------------------------------------------------------------

els.connect.addEventListener("click", connect);
els.lookup.addEventListener("click", lookup);
els.commit.addEventListener("click", commit);
els.declare.addEventListener("click", declare);
els.rotate.addEventListener("click", rotate);
for (const el of [els.scheme, els.fp, els.kind, els.doc, els.uri, els.newController]) {
  el.addEventListener("input", refresh);
}
refresh();
describeNet();
