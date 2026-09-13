// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Minimal interfaces for the ZKPassport RootVerifier and its
///         VerifierHelper, vendored from zkpassport/zkpassport-packages
///         (packages/registry-contracts). Only what PassportController uses.
///
///         RootVerifier is deployed at the same address on every supported
///         network: 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8.

struct ProofVerificationData {
    bytes32 vkeyHash;
    bytes proof;
    bytes32[] publicInputs;
}

struct ServiceConfig {
    uint256 validityPeriodInSeconds;
    string domain;
    string scope;
    bool devMode;
}

struct ProofVerificationParams {
    bytes32 version;
    ProofVerificationData proofVerificationData;
    bytes committedInputs;
    ServiceConfig serviceConfig;
}

struct BoundData {
    address senderAddress;
    uint256 chainId;
    string customData;
}

enum NullifierType {
    NON_SALTED_NULLIFIER,
    SALTED_NULLIFIER,
    NON_SALTED_MOCK_NULLIFIER,
    SALTED_MOCK_NULLIFIER,
    NONE_NULLIFIER
}

interface IVerifierHelper {
    function verifyScopes(bytes32[] calldata publicInputs, string calldata scope, string calldata subscope)
        external
        view
        returns (bool);
    function getBoundData(bytes calldata committedInputs) external view returns (BoundData memory boundData);
    function getNullifierType(bytes32[] calldata publicInputs) external view returns (NullifierType);
}

interface IZKPassportRootVerifier {
    function verify(ProofVerificationParams calldata params)
        external
        view
        returns (bool valid, bytes32 uniqueIdentifier, IVerifierHelper helper);
}
