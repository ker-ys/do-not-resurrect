// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DirectiveRegistry} from "../src/DirectiveRegistry.sol";
import {PassportController} from "../src/PassportController.sol";
import {IZKPassportRootVerifier} from "../src/zkpassport/IZKPassport.sol";

/// @notice Deploys the registry and the passport controller via CREATE2 with
///         fixed salts, so addresses match on every chain.
///         ZKPassport RootVerifier is at the same address on all networks.
contract Deploy is Script {
    bytes32 constant REGISTRY_SALT = keccak256("ker-ys/do-not-resurrect/registry/v1");
    bytes32 constant CONTROLLER_SALT = keccak256("ker-ys/do-not-resurrect/passport-controller/v1");
    address constant ZKPASSPORT_ROOT_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    function run() external {
        string memory domain = vm.envOr("DNR_DOMAIN", string("donotresurrect.eth"));
        vm.startBroadcast();
        DirectiveRegistry reg = new DirectiveRegistry{salt: REGISTRY_SALT}();
        PassportController pc = new PassportController{salt: CONTROLLER_SALT}(
            reg, IZKPassportRootVerifier(ZKPASSPORT_ROOT_VERIFIER), domain
        );
        vm.stopBroadcast();
        console.log("DirectiveRegistry:  ", address(reg));
        console.log("PassportController: ", address(pc));
        console.log("domain:             ", domain);
    }
}
