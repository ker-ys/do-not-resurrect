// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DirectiveRegistry} from "../src/DirectiveRegistry.sol";
import {PassportController} from "../src/PassportController.sol";
import {IZKPassportRootVerifier, ProofVerificationParams, NullifierType} from "../src/zkpassport/IZKPassport.sol";
import {MockRootVerifier} from "./mocks/MockRootVerifier.sol";

contract PassportControllerTest is Test {
    DirectiveRegistry reg;
    MockRootVerifier mock;
    PassportController pc;

    bytes32 subject = keccak256("genome-fingerprint:alice");
    bytes32 aliceNull = keccak256("passport:alice");
    bytes32 bobNull = keccak256("passport:bob");
    address relayer = address(0xBEEF);
    address eoa = address(0xCAFE);

    uint8 constant DNR = 1;
    uint8 constant RES = 3;

    function setUp() public {
        reg = new DirectiveRegistry();
        mock = new MockRootVerifier();
        pc = new PassportController(reg, IZKPassportRootVerifier(address(mock)), "donotresurrect.example");
    }

    // -- helpers ---------------------------------------------------------

    function _dir(uint8 kind, uint64 nonce) internal view returns (DirectiveRegistry.Directive memory d) {
        d.subject = subject;
        d.kind = kind;
        d.uri = "";
        d.nonce = nonce;
    }

    function _params(bool devMode) internal pure returns (ProofVerificationParams memory p) {
        p.serviceConfig.devMode = devMode;
    }

    function _hex(bytes32 v) internal pure returns (string memory) {
        return vm.toLowercase(vm.toString(v));
    }

    function _bindDeclare(DirectiveRegistry.Directive memory d) internal {
        mock.setBound(address(0), block.chainid, _hex(pc.declareBinding(d)));
    }

    function _claim() internal {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        vm.prank(relayer);
        pc.declare(d, _params(false));
    }

    // -- happy path ------------------------------------------------------

    function test_hexMatchesFoundryToString() public view {
        bytes32 v = 0x00ab00000000000000000000000000000000000000000000000000000000ffee;
        // Foundry's toString gives lowercase 0x-prefixed hex; our contract must agree byte for byte.
        assertEq(_hex(v), "0x00ab00000000000000000000000000000000000000000000000000000000ffee");
    }

    function test_claimViaPassport() public {
        _claim();
        assertEq(reg.controllerOf(subject), address(pc));
        assertEq(reg.currentKind(subject), DNR);
        assertEq(pc.holderOf(subject), aliceNull);
    }

    function test_updateViaSamePassport() public {
        _claim();
        DirectiveRegistry.Directive memory d = _dir(RES, 1);
        _bindDeclare(d);
        pc.declare(d, _params(false));
        assertEq(reg.currentKind(subject), RES);
    }

    function test_rotateOutThenBack() public {
        _claim();
        // passport hands control to an EOA
        mock.setBound(address(0), block.chainid, _hex(pc.rotateBinding(subject, eoa, 1)));
        pc.rotate(subject, eoa, _params(false));
        assertEq(reg.controllerOf(subject), eoa);

        // EOA declares on its own
        vm.prank(eoa);
        reg.declare(_dir(RES, 2));

        // EOA hands control back to the passport controller
        vm.prank(eoa);
        reg.rotate(subject, address(pc));

        // same passport still holds authority; a different one does not
        DirectiveRegistry.Directive memory d = _dir(DNR, 4);
        _bindDeclare(d);
        mock.set(true, bobNull, true, NullifierType.SALTED_NULLIFIER);
        vm.expectRevert(abi.encodeWithSelector(PassportController.NotHolder.selector, aliceNull, bobNull));
        pc.declare(d, _params(false));

        mock.set(true, aliceNull, true, NullifierType.SALTED_NULLIFIER);
        pc.declare(d, _params(false));
        assertEq(reg.currentKind(subject), DNR);
    }

    // -- rejections ------------------------------------------------------

    function test_invalidProof() public {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        mock.set(false, aliceNull, true, NullifierType.SALTED_NULLIFIER);
        vm.expectRevert(PassportController.InvalidProof.selector);
        pc.declare(d, _params(false));
    }

    function test_wrongScope() public {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        mock.set(true, aliceNull, false, NullifierType.SALTED_NULLIFIER);
        vm.expectRevert(PassportController.WrongScope.selector);
        pc.declare(d, _params(false));
    }

    function test_wrongChain() public {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        mock.setBound(address(0), 1, _hex(pc.declareBinding(d)));
        vm.expectRevert(abi.encodeWithSelector(PassportController.WrongChain.selector, block.chainid, 1));
        pc.declare(d, _params(false));
    }

    function test_bindingMustMatchDirective() public {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory shown = _dir(DNR, 0);
        DirectiveRegistry.Directive memory swapped = _dir(RES, 0);
        _bindDeclare(shown);
        vm.expectRevert(PassportController.WrongBinding.selector);
        pc.declare(swapped, _params(false));
    }

    function test_proofCannotReplay() public {
        _claim();
        // same binding (nonce 0) again: registry nonce is now 1, so the bound directive is stale
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        vm.expectRevert(abi.encodeWithSelector(DirectiveRegistry.BadNonce.selector, uint64(1), uint64(0)));
        pc.declare(d, _params(false));
    }

    function test_mockNullifierRejectedOutsideDevMode() public {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        mock.set(true, aliceNull, true, NullifierType.SALTED_MOCK_NULLIFIER);
        vm.expectRevert(PassportController.MockNullifier.selector);
        pc.declare(d, _params(false));
        // allowed in dev mode (testnets only; RootVerifier ignores devMode on mainnet)
        pc.declare(d, _params(true));
        assertEq(reg.currentKind(subject), DNR);
    }

    function test_noNullifierRejected() public {
        pc.commit(subject);
        vm.roll(block.number + 1);
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        mock.set(true, aliceNull, true, NullifierType.NONE_NULLIFIER);
        vm.expectRevert(PassportController.NoNullifier.selector);
        pc.declare(d, _params(false));
    }

    function test_rotateRequiresHolder() public {
        _claim();
        mock.set(true, bobNull, true, NullifierType.SALTED_NULLIFIER);
        mock.setBound(address(0), block.chainid, _hex(pc.rotateBinding(subject, eoa, 1)));
        vm.expectRevert(abi.encodeWithSelector(PassportController.NotHolder.selector, aliceNull, bobNull));
        pc.rotate(subject, eoa, _params(false));
    }

    function test_declareWithoutCommitFails() public {
        DirectiveRegistry.Directive memory d = _dir(DNR, 0);
        _bindDeclare(d);
        vm.expectRevert(DirectiveRegistry.NoCommitment.selector);
        pc.declare(d, _params(false));
    }
}
