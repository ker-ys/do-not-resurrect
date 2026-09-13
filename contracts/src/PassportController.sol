// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {DirectiveRegistry} from "./DirectiveRegistry.sol";
import {
    IZKPassportRootVerifier,
    IVerifierHelper,
    ProofVerificationParams,
    BoundData,
    NullifierType
} from "./zkpassport/IZKPassport.sol";

/// @title PassportController
/// @notice A DirectiveRegistry controller that acts on behalf of a passport
///         holder. Instead of a private key, authority over a subject is a
///         ZKPassport nullifier: a stable, unlinkable identifier derived from
///         the passport for this app's domain and scope.
///
///         Set this contract as the controller of your subject and you can
///         update your directive from any device, with any wallet or none,
///         for as long as you can produce a passport proof. Lose every key
///         you own and you still control your record. Lose the passport and
///         renew it: the nullifier is derived from the holder, not the
///         document number.
///
/// @dev    Every proof is bound (via ZKPassport's `bind` feature) to
///         - this chain id, and
///         - a hash of the exact action being authorised (declare or rotate,
///           including the registry nonce).
///         So a proof cannot be replayed, redirected to another subject, or
///         used to record a different directive than the one shown to the
///         holder when they scanned.
///
///         The registry's commit-reveal first claim still applies. Anyone may
///         post the commitment for this controller; the claim itself needs a
///         proof, so there is nothing to front-run.
contract PassportController {
    DirectiveRegistry public immutable registry;
    IZKPassportRootVerifier public immutable verifier;

    /// @notice The ZKPassport domain the proof must be scoped to.
    string public domain;
    /// @notice The ZKPassport scope (sub-scope under the domain).
    string public constant SCOPE = "dnr";

    /// @notice subject => passport nullifier holding authority over it.
    ///         Set on first declaration through this controller and never
    ///         cleared, so a subject rotated away to an EOA and later rotated
    ///         back is still owned by the same passport.
    mapping(bytes32 subject => bytes32 nullifier) public holderOf;

    event Committed(bytes32 indexed subject);
    event Claimed(bytes32 indexed subject, bytes32 indexed nullifier);
    event DeclaredByPassport(bytes32 indexed subject, bytes32 indexed nullifier, uint8 kind, uint64 nonce);
    event RotatedByPassport(bytes32 indexed subject, bytes32 indexed nullifier, address newController);

    error InvalidProof();
    error WrongScope();
    error WrongChain(uint256 expected, uint256 got);
    error WrongBinding();
    error NoNullifier();
    error MockNullifier();
    error NotHolder(bytes32 expected, bytes32 got);

    constructor(DirectiveRegistry _registry, IZKPassportRootVerifier _verifier, string memory _domain) {
        registry = _registry;
        verifier = _verifier;
        domain = _domain;
    }

    // ---------------------------------------------------------------------
    // Binding hashes. The PWA computes the same value and passes it as the
    // proof's custom_data (as a lowercase 0x-prefixed hex string).
    // ---------------------------------------------------------------------

    function declareBinding(DirectiveRegistry.Directive calldata d) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "dnr.declare", address(this), d.subject, d.kind, d.conditionsHash, keccak256(bytes(d.uri)), d.nonce
            )
        );
    }

    function rotateBinding(bytes32 subject, address newController, uint64 nonce) public view returns (bytes32) {
        return keccak256(abi.encode("dnr.rotate", address(this), subject, newController, nonce));
    }

    // ---------------------------------------------------------------------
    // Writes
    // ---------------------------------------------------------------------

    /// @notice Post the registry commitment for claiming `subject` with this
    ///         controller. Anyone may call. Wait one block, then `declare`.
    function commit(bytes32 subject) external {
        registry.commit(registry.commitmentFor(subject, address(this)));
        emit Committed(subject);
    }

    /// @notice Record a directive for `d.subject` authorised by a passport
    ///         proof bound to `declareBinding(d)`. First use for a subject
    ///         claims it for this nullifier; later uses must match.
    function declare(DirectiveRegistry.Directive calldata d, ProofVerificationParams calldata params) external {
        bytes32 nullifier = _verify(params, declareBinding(d));

        bytes32 existing = holderOf[d.subject];
        if (existing == bytes32(0)) {
            holderOf[d.subject] = nullifier;
            emit Claimed(d.subject, nullifier);
        } else if (existing != nullifier) {
            revert NotHolder(existing, nullifier);
        }

        registry.declare(d);
        emit DeclaredByPassport(d.subject, nullifier, d.kind, d.nonce);
    }

    /// @notice Move the registry controller for `subject` to `newController`,
    ///         authorised by the holding passport. Use this to hand control to
    ///         an EOA or smart account. Rotate back to this contract from that
    ///         account to return to passport control.
    function rotate(bytes32 subject, address newController, ProofVerificationParams calldata params) external {
        uint64 nonce = registry.nonceOf(subject);
        bytes32 nullifier = _verify(params, rotateBinding(subject, newController, nonce));
        if (holderOf[subject] != nullifier) revert NotHolder(holderOf[subject], nullifier);
        registry.rotate(subject, newController);
        emit RotatedByPassport(subject, nullifier, newController);
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _verify(ProofVerificationParams calldata params, bytes32 binding) internal view returns (bytes32) {
        (bool valid, bytes32 nullifier, IVerifierHelper helper) = verifier.verify(params);
        if (!valid) revert InvalidProof();

        bytes32[] calldata publicInputs = params.proofVerificationData.publicInputs;
        if (!helper.verifyScopes(publicInputs, domain, SCOPE)) revert WrongScope();

        NullifierType nt = helper.getNullifierType(publicInputs);
        if (nt == NullifierType.NONE_NULLIFIER || nullifier == bytes32(0)) revert NoNullifier();
        if (
            !params.serviceConfig.devMode
                && (nt == NullifierType.NON_SALTED_MOCK_NULLIFIER || nt == NullifierType.SALTED_MOCK_NULLIFIER)
        ) revert MockNullifier();

        BoundData memory bound = helper.getBoundData(params.committedInputs);
        if (bound.chainId != block.chainid) revert WrongChain(block.chainid, bound.chainId);
        if (keccak256(bytes(bound.customData)) != keccak256(bytes(_hex(binding)))) revert WrongBinding();

        return nullifier;
    }

    /// @dev Lowercase 0x-prefixed hex of a bytes32, matching what the PWA
    ///      puts in custom_data.
    function _hex(bytes32 v) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory s = new bytes(66);
        s[0] = "0";
        s[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            s[2 + i * 2] = alphabet[uint8(v[i] >> 4)];
            s[3 + i * 2] = alphabet[uint8(v[i] & 0x0f)];
        }
        return string(s);
    }
}
