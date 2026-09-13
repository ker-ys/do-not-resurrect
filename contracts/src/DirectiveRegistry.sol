// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title DirectiveRegistry
/// @notice A registry of posthumous directives about whether a person may be
///         reconstructed, emulated, or otherwise resurrected from a preserved
///         connectome, scan, or tissue. The latest directive recorded for a
///         subject is the binding one. Nothing here enforces anything; the
///         registry exists so that a future party holding someone's brain can
///         find an unforgeable, timestamped statement of what that person wanted.
///
/// @dev    Design summary (full spec in README):
///         - A subject is a bytes32 identity commitment. The recommended scheme
///           is a hash of a canonical genome fingerprint, because DNA is the one
///           identifier a resurrector can actually check against preserved tissue.
///         - Each subject has one controller address. The first declaration for
///           a subject claims it (after a commit-reveal step to prevent
///           front-running). Later declarations must come from the controller.
///         - "Latest wins" is decided by chain order, never by any timestamp
///           inside a message. The contract is the clock.
///         - Directives can be submitted directly by the controller or as an
///           EIP-712 signed message relayed by anyone.
///         - The schema is stored onchain so the record is self-describing.
contract DirectiveRegistry {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @notice What the subject wants done. Stored as uint8; names below.
    ///   0 NONE               No directive on file (withdrawn / never set).
    ///   1 DO_NOT_RESURRECT   Do not reconstruct, emulate, or revive in any form.
    ///   2 RESURRECT_ONLY_IF  Permitted only under the conditions referenced.
    ///   3 RESURRECT          Permitted; conditions (if any) are preferences.
    uint8 public constant KIND_NONE = 0;
    uint8 public constant KIND_DO_NOT_RESURRECT = 1;
    uint8 public constant KIND_RESURRECT_ONLY_IF = 2;
    uint8 public constant KIND_RESURRECT = 3;
    uint8 public constant KIND_MAX = 3;

    /// @notice A directive as submitted. `nonce` must equal the subject's
    ///         current nonce; it exists to prevent replay of signed directives.
    struct Directive {
        bytes32 subject;
        uint8 kind;
        bytes32 conditionsHash; // keccak256 of the conditions document, or 0
        string uri; // optional pointer to the conditions document
        uint64 nonce;
    }

    /// @notice The stored state for a subject.
    struct Record {
        address controller;
        uint8 kind;
        bytes32 conditionsHash;
        string uri;
        uint64 nonce; // number of declarations so far
        uint64 blockNumber; // block of the latest declaration
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    mapping(bytes32 subject => Record) internal _records;

    /// @notice Commitments for claiming a new subject. Value is the block the
    ///         commitment was made in.
    mapping(bytes32 commitment => uint256 blockNumber) public commitments;

    /// @dev Minimum blocks between commit and first declaration.
    uint256 public constant COMMIT_DELAY = 1;

    // ---------------------------------------------------------------------
    // EIP-712
    // ---------------------------------------------------------------------

    bytes32 public constant DIRECTIVE_TYPEHASH =
        keccak256("Directive(bytes32 subject,uint8 kind,bytes32 conditionsHash,string uri,uint64 nonce)");

    bytes32 public constant ROTATE_TYPEHASH = keccak256("Rotate(bytes32 subject,address newController,uint64 nonce)");

    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    string public constant NAME = "DirectiveRegistry";
    string public constant VERSION = "1";

    /// @notice Human-readable schema, stored onchain so the record can be read
    ///         without any offchain documentation surviving.
    string public constant SCHEMA = "DirectiveRegistry v1. "
        "subject: bytes32 identity commitment (recommended: keccak256 of a canonical genome fingerprint). "
        "kind: 0=NONE 1=DO_NOT_RESURRECT 2=RESURRECT_ONLY_IF 3=RESURRECT. "
        "conditionsHash: keccak256 of a conditions document, or zero. " "uri: optional pointer to that document. "
        "The declaration with the highest block number for a subject is binding. "
        "Timestamps inside documents are not authoritative; chain order is.";

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Committed(bytes32 indexed commitment, uint256 blockNumber);

    event Declared(
        bytes32 indexed subject,
        address indexed controller,
        uint8 kind,
        bytes32 conditionsHash,
        string uri,
        uint64 nonce
    );

    event ControllerRotated(bytes32 indexed subject, address indexed oldController, address indexed newController);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InvalidKind(uint8 kind);
    error BadNonce(uint64 expected, uint64 given);
    error NotController(address caller, address controller);
    error NoCommitment();
    error CommitmentTooRecent();
    error InvalidSignature();
    error ZeroAddress();

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getRecord(bytes32 subject) external view returns (Record memory) {
        return _records[subject];
    }

    function controllerOf(bytes32 subject) external view returns (address) {
        return _records[subject].controller;
    }

    function nonceOf(bytes32 subject) external view returns (uint64) {
        return _records[subject].nonce;
    }

    /// @notice The kind currently binding for a subject. Returns KIND_NONE if
    ///         the subject was never claimed or the directive was withdrawn.
    function currentKind(bytes32 subject) external view returns (uint8) {
        return _records[subject].kind;
    }

    function kindName(uint8 kind) external pure returns (string memory) {
        if (kind == KIND_NONE) return "NONE";
        if (kind == KIND_DO_NOT_RESURRECT) return "DO_NOT_RESURRECT";
        if (kind == KIND_RESURRECT_ONLY_IF) return "RESURRECT_ONLY_IF";
        if (kind == KIND_RESURRECT) return "RESURRECT";
        revert InvalidKind(kind);
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this)
            )
        );
    }

    function hashDirective(Directive calldata d) public pure returns (bytes32) {
        return keccak256(
            abi.encode(DIRECTIVE_TYPEHASH, d.subject, d.kind, d.conditionsHash, keccak256(bytes(d.uri)), d.nonce)
        );
    }

    /// @notice Compute the commitment a would-be controller must post before
    ///         claiming a subject.
    function commitmentFor(bytes32 subject, address controller) public pure returns (bytes32) {
        return keccak256(abi.encode(subject, controller));
    }

    // ---------------------------------------------------------------------
    // Writes
    // ---------------------------------------------------------------------

    /// @notice Post a commitment to claim a subject. Required before the first
    ///         declaration for that subject. Prevents an observer from
    ///         front-running a first declaration with their own controller.
    function commit(bytes32 commitment) external {
        commitments[commitment] = block.number;
        emit Committed(commitment, block.number);
    }

    /// @notice Declare a directive directly. `msg.sender` is the controller.
    function declare(Directive calldata d) external {
        _declare(d, msg.sender);
    }

    /// @notice Declare a directive on behalf of its signer. Anyone can relay.
    function declareSigned(Directive calldata d, bytes calldata signature) external {
        address signer = _recover(hashDirective(d), signature);
        _declare(d, signer);
    }

    /// @notice Hand control of a subject to a new address. Direct call.
    function rotate(bytes32 subject, address newController) external {
        _rotate(subject, newController, msg.sender);
    }

    /// @notice Hand control of a subject to a new address. Signed by the
    ///         current controller, relayed by anyone.
    function rotateSigned(bytes32 subject, address newController, uint64 nonce, bytes calldata signature) external {
        Record storage r = _records[subject];
        if (nonce != r.nonce) revert BadNonce(r.nonce, nonce);
        bytes32 structHash = keccak256(abi.encode(ROTATE_TYPEHASH, subject, newController, nonce));
        address signer = _recover(structHash, signature);
        _rotate(subject, newController, signer);
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _declare(Directive calldata d, address actor) internal {
        if (d.kind > KIND_MAX) revert InvalidKind(d.kind);
        Record storage r = _records[d.subject];
        if (d.nonce != r.nonce) revert BadNonce(r.nonce, d.nonce);

        if (r.controller == address(0)) {
            // First claim: require a sufficiently old commitment.
            bytes32 c = commitmentFor(d.subject, actor);
            uint256 committedAt = commitments[c];
            if (committedAt == 0) revert NoCommitment();
            if (block.number < committedAt + COMMIT_DELAY) revert CommitmentTooRecent();
            delete commitments[c];
            r.controller = actor;
        } else if (actor != r.controller) {
            revert NotController(actor, r.controller);
        }

        r.kind = d.kind;
        r.conditionsHash = d.conditionsHash;
        r.uri = d.uri;
        r.blockNumber = uint64(block.number);
        r.nonce = d.nonce + 1;

        emit Declared(d.subject, actor, d.kind, d.conditionsHash, d.uri, d.nonce);
    }

    function _rotate(bytes32 subject, address newController, address actor) internal {
        if (newController == address(0)) revert ZeroAddress();
        Record storage r = _records[subject];
        if (actor != r.controller || actor == address(0)) revert NotController(actor, r.controller);
        r.controller = newController;
        r.nonce += 1;
        emit ControllerRotated(subject, actor, newController);
    }

    function _recover(bytes32 structHash, bytes calldata signature) internal view returns (address) {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
        bytes32 rs;
        bytes32 ss;
        uint8 v;
        assembly {
            rs := calldataload(signature.offset)
            ss := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        // Reject malleable signatures (high-s).
        if (uint256(ss) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }
        if (v != 27 && v != 28) revert InvalidSignature();
        address signer = ecrecover(digest, v, rs, ss);
        if (signer == address(0)) revert InvalidSignature();
        return signer;
    }
}
