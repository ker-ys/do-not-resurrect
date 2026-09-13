# Do Not Resurrect

Control your connectome. An onchain registry of posthumous directives: whether a person consents to being reconstructed, emulated, or revived from a preserved brain, scan, or tissue.

The registry enforces nothing. It exists so that whoever holds your connectome in a century can find an unforgeable, timestamped statement of what you wanted, in a place that does not depend on any company, hospital, or government still existing.

**The latest directive recorded for a subject is binding.** Recency is chain order. There is no death oracle: the living update their directive by recording a new one, the dead cannot, so their last word stands.

A [Ys](https://github.com/ker-ys) project.

## Layout

| Path | What |
|---|---|
| [`contracts/`](contracts/) | Foundry project. `DirectiveRegistry.sol`, `PassportController.sol`, tests, CREATE2 deploy script. |
| [`web/`](web/) | Installable PWA. Builds to a single directory for pinning to IPFS. Talks to the chain directly. |
| [`spec/`](spec/) | The directive spec: record model, subject commitment schemes, signed message format, how to read a record. |

## How it works

1. A **subject** is a 32-byte identity commitment. The recommended scheme is a hash of your genome fingerprint, because DNA is the one identifier a resurrector can actually check against preserved tissue. Passports and wallets will mean nothing by then.
2. You **commit** to claiming the subject, wait a block, then **declare** a directive. The first declaration makes your key the subject's controller.
3. Directives are one of `DO_NOT_RESURRECT`, `RESURRECT_ONLY_IF` (with a conditions document), `RESURRECT`, or `NONE` to withdraw.
4. Update any time. Latest wins. Rotate the controller key when you like.
5. If you lose the key, the record freezes at its last state. A frozen `DO_NOT_RESURRECT` is the safe failure mode.

### Your passport as the key

You do not need to keep a private key alive for decades. `PassportController` is a registry controller that answers to a [ZKPassport](https://zkpassport.id) proof instead of a wallet. Set it as your subject's controller and every update is authorised by scanning your passport in the ZKPassport app. The proof reveals nothing about you; it commits to a stable per-passport nullifier, to this chain, and to the hash of the exact directive you are recording, so it cannot be replayed or redirected. Renew the passport and the nullifier stays the same. Rotate to a wallet and back whenever you like; the same passport keeps its authority.

The PWA in `web/` walks through both paths.

Full details in [`spec/SPEC.md`](spec/SPEC.md).

## Deployments

Deployed via CREATE2, so addresses are the same on every chain. Canonical deployment will be Ethereum mainnet; until then, Sepolia.

| Chain | DirectiveRegistry | PassportController | ZKPassport domain |
|---|---|---|---|
| Sepolia (11155111) | [`0xD0782096437b6c2B668E64717556fE73f5C72eF4`](https://sepolia.etherscan.io/address/0xD0782096437b6c2B668E64717556fE73f5C72eF4) | [`0x47cF8D3281aF4d858F3fdf55662fD986274403A4`](https://sepolia.etherscan.io/address/0x47cF8D3281aF4d858F3fdf55662fD986274403A4) | donotresurrect.eth |
| Mainnet | not yet | not yet | |

ZKPassport RootVerifier: `0x1D000001000EFD9a6371f4d90bB8920D5431c0D8` on all networks.

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

Deployment addresses live in `web/src/config.ts`. The ZKPassport domain there must match the one the `PassportController` was deployed with (`DNR_DOMAIN` env for the deploy script).

## License

CC0-1.0. This is meant to outlive its authors.
