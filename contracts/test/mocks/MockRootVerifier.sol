// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    IZKPassportRootVerifier,
    IVerifierHelper,
    ProofVerificationParams,
    BoundData,
    NullifierType
} from "../../src/zkpassport/IZKPassport.sol";

/// @dev Test double for the ZKPassport RootVerifier. Acts as its own helper.
///      Everything it returns is set by the test.
contract MockRootVerifier is IZKPassportRootVerifier, IVerifierHelper {
    bool public valid = true;
    bytes32 public nullifier = keccak256("passport:alice");
    bool public scopesOk = true;
    NullifierType public nullifierType = NullifierType.SALTED_NULLIFIER;
    BoundData internal _bound;

    function set(bool _valid, bytes32 _nullifier, bool _scopesOk, NullifierType _nt) external {
        valid = _valid;
        nullifier = _nullifier;
        scopesOk = _scopesOk;
        nullifierType = _nt;
    }

    function setBound(address sender, uint256 chainId, string calldata customData) external {
        _bound = BoundData(sender, chainId, customData);
    }

    function verify(ProofVerificationParams calldata) external view returns (bool, bytes32, IVerifierHelper) {
        return (valid, nullifier, IVerifierHelper(address(this)));
    }

    function verifyScopes(bytes32[] calldata, string calldata, string calldata) external view returns (bool) {
        return scopesOk;
    }

    function getBoundData(bytes calldata) external view returns (BoundData memory) {
        return _bound;
    }

    function getNullifierType(bytes32[] calldata) external view returns (NullifierType) {
        return nullifierType;
    }
}
