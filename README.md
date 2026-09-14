# Do Not Resurrect

Control your connectome.

An onchain registry of posthumous directives: whether you consent to being reconstructed, emulated, or revived from a preserved brain, a scan, or tissue. Record it once, update it whenever you like, and it outlives every company, hospital, and government that might otherwise hold the paperwork.

The registry enforces nothing. It exists so that whoever holds your connectome in a century can find an unforgeable, timestamped statement of what you wanted, and can never claim they did not know.

**The latest directive recorded for a subject is binding.** Recency is chain order. There is no death oracle: the living update their directive by recording a new one, the dead cannot, so their last word stands.

A [Ys](https://github.com/ker-ys) project. CC0.

## Status

Live on Sepolia and smoke-tested. Mainnet deployment and the IPFS-pinned app are next. Treat the spec as v1 draft; the contract interface is stable, the genome fingerprint canonicalisation is not yet written.

## Layout

| Path | What |
|---|---|
| [`contracts/`](contracts/) | Foundry project. `DirectiveRegistry.sol`, `PassportController.sol`, tests, CREATE2 deploy script. |
| [`web/`](web/) | Installable PWA. Builds to a single directory for pinning to IPFS. Talks to the chain directly, no backend. |
| [`spec/`](spec/) | The directive spec: record model, subject commitment schemes, signed message format, how to read a record in 2140. |

## How it works

1. A **subject** is a 32-byte identity commitment. The recommended scheme is a hash of your genome fingerprint, because DNA is the one identifier a resurrector can actually check against preserved tissue. Passports and wallets will mean nothing by then.
2. You **commit** to claiming the subject, wait a block, then **declare** a directive. The first declaration makes you the subject's controller. The commit step stops anyone from front-running your claim.
3. Directives are one of `DO_NOT_RESURRECT`, `RESURRECT_ONLY_IF` (with a conditions document), `RESURRECT`, or `NONE` to withdraw.
4. Update any time. Latest wins. Rotate the controller when you like.
5. If you lose the controller key, the record freezes at its last state. A frozen `DO_NOT_RESURRECT` is the safe failure mode.

The schema is stored onchain as a string, so a record can be read without any of this repository surviving.

### Your passport as the key

You do not need to keep a private key alive for decades. `PassportController` is a registry controller that answers to a [ZKPassport](https://zkpassport.id) proof instead of a wallet. Set it as your subject's controller and every update is authorised by scanning your passport in the ZKPassport app.

The proof reveals nothing about you. It commits to a stable per-passport nullifier, to this chain, and to the hash of the exact directive you are recording, so it cannot be replayed, and you cannot be shown one directive and have another recorded. Renew the passport and the nullifier stays the same. Rotate to a wallet and back whenever you like; the same passport keeps its authority.

### Two ways to hold a record

| Authority | Who can update | If you lose it |
|---|---|---|
| Wallet key | The key, by direct call or EIP-712 signed message relayed by anyone | Record freezes |
| Passport | Whoever can produce a ZKPassport proof for the same passport | Renew the passport; same nullifier |

Full details in [`spec/SPEC.md`](spec/SPEC.md).

## Using it

Open the app, connect a wallet on Sepolia, and:

1. **Subject.** Paste your genome fingerprint text (scheme G1) or a raw 32-byte value. The app hashes it locally and shows the subject.
2. **Directive.** Pick a kind. Optionally paste a conditions document; only its keccak256 goes onchain, plus an optional URI to where you keep it.
3. **Authority.** Passport (recommended) or wallet key.
4. **Commit**, wait one block, **Declare**. On the passport path Declare shows a QR code or deep link for the ZKPassport app; the proof comes back to the page and is submitted with the directive.

**Look up** shows the current record for any subject. **Rotate** hands control to another address, or back to the passport controller.

Reading a record from the command line, no app needed:

```sh
REG=0xD0782096437b6c2B668E64717556fE73f5C72eF4
RPC=https://ethereum-sepolia-rpc.publicnode.com
SUBJECT=0x...   # the 32-byte subject commitment

cast call $REG 'getRecord(bytes32)((address,uint8,bytes32,string,uint64,uint64))' $SUBJECT -r $RPC
#            controller, kind, conditionsHash, uri, nonce, blockNumber
cast call $REG 'kindName(uint8)(string)' 1 -r $RPC     # DO_NOT_RESURRECT
cast call $REG 'SCHEMA()(string)' -r $RPC              # the onchain schema
```

## Deployments

Deployed through the deterministic CREATE2 deployer, so addresses are the same on every chain. Canonical deployment will be Ethereum mainnet; until then, Sepolia.

| Chain | DirectiveRegistry | PassportController | ZKPassport domain |
|---|---|---|---|
| Sepolia (11155111) | [`0xD0782096437b6c2B668E64717556fE73f5C72eF4`](https://sepolia.etherscan.io/address/0xD0782096437b6c2B668E64717556fE73f5C72eF4) | [`0x47cF8D3281aF4d858F3fdf55662fD986274403A4`](https://sepolia.etherscan.io/address/0x47cF8D3281aF4d858F3fdf55662fD986274403A4) | `donotresurrect.eth` |
| Mainnet | not yet | not yet | |

Both are source-verified on [Sourcify](https://sourcify.dev). ZKPassport's RootVerifier is `0x1D000001000EFD9a6371f4d90bB8920D5431c0D8` on all networks.

## Development

```sh
# contracts
cd contracts
forge build
forge test

# web
cd web
npm install
npm run abi       # regenerate src/abi.ts from contracts/out
npm run dev
npm run build     # -> web/dist, pin this directory to IPFS
```

Deploying to another chain:

```sh
cd contracts
DNR_DOMAIN=donotresurrect.eth forge script script/Deploy.s.sol --rpc-url $RPC --broadcast
```

Addresses live in `web/src/config.ts`. The ZKPassport domain there must equal the one the `PassportController` was deployed with, or proofs fail scope verification. Testnet deployments run with `devMode: true`, which accepts ZKPassport's mock passports; the RootVerifier ignores dev mode on mainnet.

## What this is not

- **Not enforcement.** Nothing stops someone ignoring the record. It removes their deniability.
- **Not proof of genome ownership.** Anyone can claim a subject first. A genome hash is unguessable without the genome, which protects against strangers but not against someone who has your sequence. The passport path proves the claimant is a real, unique person, not that they own the genome.
- **Not a death oracle.** The registry does not know or care whether you are alive.
- **Not audited.** Read the contracts before trusting them with anything that matters.

## Roadmap

- Real-device ZKPassport test on Sepolia
- Pin the built app to IPFS and publish the CID
- Mainnet deployment
- Canonical genome fingerprint encoding (spec scheme G1)
- Gasless relay so the passport path needs no wallet at all

## License

CC0-1.0. This is meant to outlive its authors.
