# Do Not Resurrect: directive registry specification

Version 1. Status: draft.

## 1. Purpose

A person may one day have their brain preserved, scanned, or sequenced well enough that someone could attempt to reconstruct or emulate them. This registry lets a living person record, in a tamper-evident and institution-independent way, whether they consent to that.

The registry does not enforce anything. It exists so that a future party holding a brain, a scan, or tissue can find an unforgeable, timestamped statement of what its owner wanted, and cannot later claim they did not know.

## 2. Design principles

1. **Latest wins.** The most recent directive recorded for a subject is the binding one. Recency is decided by chain order (block number), never by any timestamp inside a message or document.
2. **No death oracle.** The registry has no notion of the subject being alive or dead. A living person updates their directive by recording a new one. A dead person cannot, so their last directive stands.
3. **Identity is data, not a key.** The identifier a resurrector can actually check (the genome) is not secret and must not be the thing that authorises writes. Writes are authorised by a controller key. The subject commitment is what the resurrector searches by.
4. **Self-describing.** The schema is stored onchain. A reader in 2140 should be able to interpret a record from chain data alone.
5. **Chain longevity over convenience.** Deploy to the chain most likely to still exist in a century. Ethereum mainnet is the canonical deployment. Other deployments are mirrors and the mainnet record wins on conflict.

## 3. Record model

Each **subject** (a `bytes32` identity commitment) has one **record**:

| Field | Type | Meaning |
|---|---|---|
| controller | address | The key allowed to update this record |
| kind | uint8 | The directive, see section 4 |
| conditionsHash | bytes32 | keccak256 of a conditions document, or zero |
| uri | string | Optional pointer to that document (ipfs://, ar://, https://) |
| nonce | uint64 | Number of state changes so far; replay protection |
| blockNumber | uint64 | Block of the latest directive |

## 4. Directive kinds

| Value | Name | Meaning |
|---|---|---|
| 0 | NONE | No directive. Used to withdraw from the registry. The controller keeps the slot. |
| 1 | DO_NOT_RESURRECT | Do not reconstruct, emulate, simulate, or revive the subject in any form, from any substrate. |
| 2 | RESURRECT_ONLY_IF | Reconstruction is permitted only if the conditions in the referenced document are met. |
| 3 | RESURRECT | Reconstruction is permitted. A conditions document, if present, expresses preferences rather than requirements. |

A reader encountering a kind value above 3 should treat the record as malformed and fall back to the previous valid directive for that subject, found via the `Declared` event log.

## 5. Subject commitment schemes

The contract treats `subject` as an opaque 32-byte value. The choice of scheme is the subject's, but the scheme must be discoverable by a resurrector. Recommended: put the scheme identifier in the conditions document, and where no document exists, assume scheme G1.

### G1: genome fingerprint (recommended)

`subject = keccak256("dnr:g1:" || fingerprint)`

Where `fingerprint` is a canonical encoding of the subject's genome under a fixed reference. The exact canonicalisation is deferred to a companion document, because sequencing noise means a naive full-genome hash is not reproducible. The intent is a panel of stable, high-confidence variants, sorted, encoded deterministically.

Rationale: at resurrection time, passports, wallets, and names are meaningless. Preserved tissue has DNA. A resurrector can sequence it, compute the fingerprint, and look up the record. There is no plausible "we could not identify them."

Privacy: a genome fingerprint hash is unlinkable without the genome itself. It reveals nothing about the subject to a casual observer of the chain.

### P1: passport nullifier

`subject = zk-passport nullifier` under a named proving scheme.

For subjects who cannot or do not want to sequence. Useful at registration time, useless at resurrection time. Should be paired with a G1 record when possible; the conditions document may cross-reference them.

### X1: arbitrary

Any other `bytes32`. The subject takes responsibility for making it discoverable.

## 6. Write authorisation

### First claim

To prevent front-running, claiming a subject is a two-step process:

1. `commit(keccak256(abi.encode(subject, controller)))`
2. After at least one block, `declare(...)` or `declareSigned(...)` from `controller`.

The commitment reveals nothing about the subject. Only the committed controller can complete the claim.

### Updates

Any later `declare` must come from the current controller, either as a direct transaction or as an EIP-712 signed message relayed by anyone. The `nonce` in the directive must equal the record's current nonce.

### Rotation

The controller may hand control to a new address via `rotate` or `rotateSigned`. Rotation increments the nonce. Use this for key hygiene, for moving to a smart account, or for social recovery setups.

### Key loss

If the controller key is lost, the record is frozen at its last state. This is deliberate. A frozen DO_NOT_RESURRECT is the safe failure mode. Subjects who want recovery should set the controller to a smart account with their chosen recovery policy, or to the PassportController below.

### Passport control

`PassportController` is a contract that can be the controller of any subject. It authorises writes with a ZKPassport proof instead of a signature:

1. The proof must verify against the ZKPassport RootVerifier (same address on every supported chain).
2. It must be scoped to the controller's configured domain and the scope `dnr`.
3. It must carry a real (non-mock) nullifier unless the proof declares dev mode, which the verifier only honours on testnets.
4. It must be bound to the current chain id.
5. Its custom data must equal the lowercase hex of the **binding hash** of the action:
   - declare: `keccak256(abi.encode("dnr.declare", controller, subject, kind, conditionsHash, keccak256(uri), nonce))`
   - rotate: `keccak256(abi.encode("dnr.rotate", controller, subject, newController, nonce))`

The first declaration for a subject through the controller records the proof's nullifier as the subject's holder. Every later action must carry the same nullifier. The holder mapping is never cleared, so a subject rotated to a wallet and later rotated back is still owned by the same passport.

Because the binding includes the registry nonce, a proof authorises exactly one action and cannot be replayed. Because it includes every field of the directive, the holder cannot be shown one directive and have another recorded.

The registry's commit-reveal still applies to the first claim. Anyone may post the commitment on the controller's behalf; the claim itself needs the proof.

## 7. Signed message format

EIP-712 domain:

```
name:              "DirectiveRegistry"
version:           "1"
chainId:           <chain>
verifyingContract: <registry address>
```

Types:

```
Directive(bytes32 subject,uint8 kind,bytes32 conditionsHash,string uri,uint64 nonce)
Rotate(bytes32 subject,address newController,uint64 nonce)
```

Signatures are 65-byte `r || s || v` with `v` in {27, 28} and low-`s` only.

## 8. Reading a record

To determine the binding directive for a subject:

1. Read `getRecord(subject)` on the canonical (mainnet) deployment.
2. If `controller` is zero, no directive exists.
3. The `kind` field is the directive. `conditionsHash` and `uri` locate the conditions document. Verify the document's keccak256 against `conditionsHash` before relying on it.
4. For history, filter `Declared` events by subject.

If mirrors on other chains disagree with mainnet, mainnet wins.

## 9. Conditions document

A conditions document is any bytes whose keccak256 matches `conditionsHash`. The recommended format is a plain UTF-8 text or Markdown file, because a plain-text file is the format most likely to be readable in a century. Avoid formats needing a specific parser.

The document should state, in order:

1. The subject commitment scheme used (G1, P1, X1) and any parameters.
2. The directive in the subject's own words.
3. Conditions, if kind is RESURRECT_ONLY_IF or RESURRECT.
4. Optionally, a statement of who the subject would trust to interpret ambiguity.

Store the document somewhere content-addressed (IPFS, Arweave) and also keep copies with whoever holds your other end-of-life documents. The hash onchain is what matters; the URI is a convenience.

## 10. Out of scope for v1

- Proof that the person making the declaration is the person the genome belongs to. Anyone can claim any subject first. The genome hash is unguessable without the genome, which is protection enough against strangers, but not against someone who has your sequence. The passport controller proves the claimant is a real, unique passport holder, not that they own the genome.
- Enforcement.
- Determining death.
