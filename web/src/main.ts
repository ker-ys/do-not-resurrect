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
  zeroAddress,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from "viem";
import QRCode from "qrcode";
import { registryAbi, controllerAbi } from "./abi";
import { deployments, KIND_DESCRIPTIONS, KIND_NAMES, ZK_DOMAIN, type Deployment } from "./config";
import { requestPassportProof, toVerifierParams } from "./passport";

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
  authority: $<HTMLSelectElement>("authority"),
  authorityDesc: $("authorityDesc"),
  commit: $<HTMLButtonElement>("commit"),
  declare: $<HTMLButtonElement>("declare"),
  qr: $("qr"),
  qrLink: $<HTMLAnchorElement>("qrLink"),
  qrCanvas: $<HTMLCanvasElement>("qrCanvas"),
  qrStatus: $("qrStatus"),
  log: $<HTMLPreElement>("log"),
  newController: $<HTMLInputElement>("newController"),
  rotate: $<HTMLButtonElement>("rotate"),
};

const ZERO32 = `0x${"0".repeat(64)}` as Hex;

const AUTHORITY_DESC: Record<string, string> = {
  passport:
    "Your passport is the key. Each change needs a scan in the ZKPassport app; the proof is bound to the exact directive you see here. Lose every wallet you own and you still control the record.",
  wallet:
    "The connected wallet's private key is the controller. Lose the key and the record freezes at its last state.",
};

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

function usePassport(): boolean {
  return els.authority.value === "passport";
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
  els.authorityDesc.textContent = AUTHORITY_DESC[els.authority.value];
  const hasRegistry = !!deployment?.registry;
  const hasController = !!deployment?.controller;
  const canWrite = !!s && !!account && hasRegistry && (!usePassport() || hasController);
  els.lookup.disabled = !s || !hasRegistry;
  els.commit.disabled = !canWrite;
  els.declare.disabled = !canWrite;
  els.rotate.disabled = !canWrite || !isAddress(els.newController.value.trim());
}

function describeNet() {
  if (!deployment) {
    els.net.textContent = "No wallet connected.";
    return;
  }
  const reg = deployment.registry ?? "registry not deployed here";
  const pc = deployment.controller ?? "passport controller not deployed here";
  els.net.textContent = `${deployment.chain.name} · ${reg} · ${pc}` + (account ? ` · ${account}` : "");
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
  if (r.controller === zeroAddress) {
    els.record.textContent = "No record. Subject is unclaimed.";
    return;
  }
  const who =
    deployment.controller && r.controller.toLowerCase() === deployment.controller.toLowerCase()
      ? `${r.controller} (passport controller)`
      : r.controller;
  els.record.textContent = [
    `controller:     ${who}`,
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

async function send(
  target: "registry" | "controller",
  fn: string,
  args: readonly unknown[],
): Promise<boolean> {
  if (!walletClient || !publicClient || !deployment || !account) return false;
  const address = target === "registry" ? deployment.registry : deployment.controller;
  const abi = target === "registry" ? registryAbi : controllerAbi;
  if (!address) return false;
  try {
    const { request } = await publicClient.simulateContract({
      address,
      abi: abi as any,
      functionName: fn as any,
      args: args as any,
      account,
    });
    const hash = await walletClient.writeContract(request as any);
    log(`${fn}: sent ${hash}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    log(`${fn}: ${receipt.status} in block ${receipt.blockNumber}`);
    await lookup();
    return receipt.status === "success";
  } catch (e: any) {
    log(`${fn}: ${e.shortMessage ?? e.message ?? String(e)}`);
    return false;
  }
}

function directive(s: Hex, nonce: bigint) {
  return {
    subject: s,
    kind: Number(els.kind.value),
    conditionsHash: conditionsHash(),
    uri: els.uri.value.trim(),
    nonce,
  };
}

// ---------------------------------------------------------------------
// Passport flow
// ---------------------------------------------------------------------

async function scanForBinding(binding: Hex, purpose: string) {
  if (!deployment) throw new Error("not connected");
  const req = await requestPassportProof({
    domain: ZK_DOMAIN,
    chain: deployment.zkChain,
    devMode: deployment.devMode,
    binding,
    purpose,
  });
  els.qr.hidden = false;
  els.qrLink.href = req.url;
  els.qrStatus.textContent = "Waiting for the app…";
  await QRCode.toCanvas(els.qrCanvas, req.url, { width: 256, margin: 1 });
  req.onStatus((s) => (els.qrStatus.textContent = s));
  log(`passport: request ${req.requestId}`);
  try {
    const proof = await req.proof;
    els.qrStatus.textContent = "Proof received. Submitting…";
    return toVerifierParams(req.zk, proof, ZK_DOMAIN, deployment.devMode);
  } finally {
    setTimeout(() => (els.qr.hidden = true), 4000);
  }
}

// ---------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------

async function commit() {
  const s = subject();
  if (!s || !account || !deployment) return;
  const ok = usePassport()
    ? await send("controller", "commit", [s])
    : await send("registry", "commit", [commitmentFor(s, account)]);
  if (ok) log("Now wait one block, then Declare.");
}

async function declare() {
  const s = subject();
  if (!s || !deployment || !publicClient) return;
  const nonce = await currentNonce(s);
  const d = directive(s, nonce);
  if (!usePassport()) {
    await send("registry", "declare", [d]);
    return;
  }
  try {
    const binding = await publicClient.readContract({
      address: deployment.controller!,
      abi: controllerAbi,
      functionName: "declareBinding",
      args: [d],
    });
    const params = await scanForBinding(
      binding,
      `Record directive ${KIND_NAMES[d.kind]} for subject ${s.slice(0, 10)}…`,
    );
    await send("controller", "declare", [d, params]);
  } catch (e: any) {
    log(`passport: ${e.message ?? String(e)}`);
  }
}

async function rotate() {
  const s = subject();
  const to = els.newController.value.trim();
  if (!s || !isAddress(to) || !deployment || !publicClient) return;
  if (!usePassport()) {
    await send("registry", "rotate", [s, to]);
    return;
  }
  try {
    const nonce = await currentNonce(s);
    const binding = await publicClient.readContract({
      address: deployment.controller!,
      abi: controllerAbi,
      functionName: "rotateBinding",
      args: [s, to, nonce],
    });
    const params = await scanForBinding(binding, `Hand control of subject ${s.slice(0, 10)}… to ${to}`);
    await send("controller", "rotate", [s, to, params]);
  } catch (e: any) {
    log(`passport: ${e.message ?? String(e)}`);
  }
}

// ---------------------------------------------------------------------
// Wire up
// ---------------------------------------------------------------------

els.connect.addEventListener("click", connect);
els.lookup.addEventListener("click", lookup);
els.commit.addEventListener("click", commit);
els.declare.addEventListener("click", declare);
els.rotate.addEventListener("click", rotate);
for (const el of [els.scheme, els.fp, els.kind, els.doc, els.uri, els.newController, els.authority]) {
  el.addEventListener("input", refresh);
  el.addEventListener("change", refresh);
}
refresh();
describeNet();
