// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DirectiveRegistry} from "../src/DirectiveRegistry.sol";

contract DirectiveRegistryTest is Test {
    DirectiveRegistry reg;

    uint256 alicePk = 0xA11CE;
    address alice;
    uint256 bobPk = 0xB0B;
    address bob;

    bytes32 subject = keccak256("genome-fingerprint:alice");

    uint8 constant NONE = 0;
    uint8 constant DNR = 1;
    uint8 constant ONLY_IF = 2;
    uint8 constant RES = 3;

    function setUp() public {
        reg = new DirectiveRegistry();
        alice = vm.addr(alicePk);
        bob = vm.addr(bobPk);
    }

    // -- helpers ---------------------------------------------------------

    function _dir(uint8 kind, uint64 nonce) internal view returns (DirectiveRegistry.Directive memory d) {
        d.subject = subject;
        d.kind = kind;
        d.conditionsHash = bytes32(0);
        d.uri = "";
        d.nonce = nonce;
    }

    function _commitAs(address who) internal {
        bytes32 c = reg.commitmentFor(subject, who);
        vm.prank(who);
        reg.commit(c);
        vm.roll(block.number + 1);
    }

    function _sign(uint256 pk, DirectiveRegistry.Directive memory d) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(reg.DIRECTIVE_TYPEHASH(), d.subject, d.kind, d.conditionsHash, keccak256(bytes(d.uri)), d.nonce)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", reg.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signRotate(uint256 pk, address newController, uint64 nonce) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(reg.ROTATE_TYPEHASH(), subject, newController, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", reg.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // -- first claim -----------------------------------------------------

    function test_firstDeclareRequiresCommitment() public {
        vm.prank(alice);
        vm.expectRevert(DirectiveRegistry.NoCommitment.selector);
        reg.declare(_dir(DNR, 0));
    }

    function test_commitmentMustAge() public {
        bytes32 c = reg.commitmentFor(subject, alice);
        vm.prank(alice);
        reg.commit(c);
        vm.prank(alice);
        vm.expectRevert(DirectiveRegistry.CommitmentTooRecent.selector);
        reg.declare(_dir(DNR, 0));
    }

    function test_firstDeclareClaimsSubject() public {
        _commitAs(alice);
        vm.prank(alice);
        reg.declare(_dir(DNR, 0));

        DirectiveRegistry.Record memory r = reg.getRecord(subject);
        assertEq(r.controller, alice);
        assertEq(r.kind, DNR);
        assertEq(r.nonce, 1);
        assertEq(r.blockNumber, uint64(block.number));
        assertEq(reg.currentKind(subject), 1);
        // commitment consumed
        assertEq(reg.commitments(reg.commitmentFor(subject, alice)), 0);
    }

    function test_frontRunnerCannotClaimWithoutOwnCommitment() public {
        _commitAs(alice);
        // bob sees alice's pending declare and tries to claim first
        vm.prank(bob);
        vm.expectRevert(DirectiveRegistry.NoCommitment.selector);
        reg.declare(_dir(RES, 0));
    }

    // -- latest wins -----------------------------------------------------

    function test_latestDirectiveWins() public {
        _commitAs(alice);
        vm.startPrank(alice);
        reg.declare(_dir(DNR, 0));
        vm.roll(block.number + 100);
        reg.declare(_dir(RES, 1));
        vm.stopPrank();

        assertEq(reg.currentKind(subject), RES);
        assertEq(reg.nonceOf(subject), 2);
    }

    function test_withdrawViaKindNone() public {
        _commitAs(alice);
        vm.startPrank(alice);
        reg.declare(_dir(DNR, 0));
        reg.declare(_dir(NONE, 1));
        vm.stopPrank();
        assertEq(reg.currentKind(subject), 0);
        // still controlled by alice; slot is not released
        assertEq(reg.controllerOf(subject), alice);
    }

    function test_nonControllerCannotOverwrite() public {
        _commitAs(alice);
        vm.prank(alice);
        reg.declare(_dir(DNR, 0));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.NotController.selector, bob, alice));
        reg.declare(_dir(RES, 1));
    }

    function test_staleNonceRejected() public {
        _commitAs(alice);
        vm.startPrank(alice);
        reg.declare(_dir(DNR, 0));
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.BadNonce.selector, uint64(1), uint64(0)));
        reg.declare(_dir(RES, 0));
        vm.stopPrank();
    }

    function test_invalidKindRejected() public {
        _commitAs(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.InvalidKind.selector, uint8(9)));
        reg.declare(_dir(9, 0));
    }

    function test_conditionsStored() public {
        _commitAs(alice);
        DirectiveRegistry.Directive memory d = _dir(ONLY_IF, 0);
        d.conditionsHash = keccak256("only if my partner consents");
        d.uri = "ipfs://bafy...";
        vm.prank(alice);
        reg.declare(d);
        DirectiveRegistry.Record memory r = reg.getRecord(subject);
        assertEq(r.conditionsHash, d.conditionsHash);
        assertEq(r.uri, d.uri);
    }

    // -- signed path -----------------------------------------------------

    function test_declareSignedRelayedByAnyone() public {
        _commitAs(alice);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        bytes memory sig = _sign(alicePk, d);
        vm.prank(bob); // relayer
        reg.declareSigned(d, sig);
        assertEq(reg.controllerOf(subject), alice);
        assertEq(reg.currentKind(subject), 1);
    }

    function test_signedReplayFails() public {
        _commitAs(alice);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        bytes memory sig = _sign(alicePk, d);
        reg.declareSigned(d, sig);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.BadNonce.selector, uint64(1), uint64(0)));
        reg.declareSigned(d, sig);
    }

    function test_signedByWrongKeyIsNotController() public {
        _commitAs(alice);
        vm.prank(alice);
        reg.declare(_dir(DNR, 0));
        DirectiveRegistry.Directive memory d = _dir(RES, 1);
        bytes memory sig = _sign(bobPk, d);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.NotController.selector, bob, alice));
        reg.declareSigned(d, sig);
    }

    function test_malformedSignatureRejected() public {
        _commitAs(alice);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        vm.expectRevert(DirectiveRegistry.InvalidSignature.selector);
        reg.declareSigned(d, hex"deadbeef");
    }

    // -- rotation --------------------------------------------------------

    function test_rotateThenNewControllerDeclares() public {
        _commitAs(alice);
        vm.prank(alice);
        reg.declare(_dir(DNR, 0));
        vm.prank(alice);
        reg.rotate(subject, bob);
        assertEq(reg.controllerOf(subject), bob);
        assertEq(reg.nonceOf(subject), 2);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.NotController.selector, alice, bob));
        reg.declare(_dir(RES, 2));

        vm.prank(bob);
        reg.declare(_dir(RES, 2));
        assertEq(reg.currentKind(subject), 3);
    }

    function test_rotateSigned() public {
        _commitAs(alice);
        vm.prank(alice);
        reg.declare(_dir(DNR, 0));
        bytes memory sig = _signRotate(alicePk, bob, 1);
        reg.rotateSigned(subject, bob, 1, sig);
        assertEq(reg.controllerOf(subject), bob);
    }

    function test_rotateUnclaimedFails() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.NotController.selector, alice, address(0)));
        reg.rotate(subject, bob);
    }

    function test_rotateToZeroFails() public {
        _commitAs(alice);
        vm.prank(alice);
        reg.declare(_dir(DNR, 0));
        vm.prank(alice);
        vm.expectRevert(DirectiveRegistry.ZeroAddress.selector);
        reg.rotate(subject, address(0));
    }

    // -- misc ------------------------------------------------------------

    function test_kindNames() public view {
        assertEq(reg.kindName(0), "NONE");
        assertEq(reg.kindName(1), "DO_NOT_RESURRECT");
        assertEq(reg.kindName(2), "RESURRECT_ONLY_IF");
        assertEq(reg.kindName(3), "RESURRECT");
    }

    function test_schemaOnchain() public view {
        assertGt(bytes(reg.SCHEMA()).length, 100);
    }
}
