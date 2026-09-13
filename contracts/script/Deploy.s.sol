// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DirectiveRegistry} from "../src/DirectiveRegistry.sol";

/// @notice Deploys the registry via CREATE2 with a fixed salt so the address
///         is the same on every chain it is deployed to.
contract Deploy is Script {
    bytes32 constant SALT = keccak256("ker-ys/do-not-resurrect/v1");

    function run() external {
        vm.startBroadcast();
        DirectiveRegistry reg = new DirectiveRegistry{salt: SALT}();
        vm.stopBroadcast();
        console.log("DirectiveRegistry:", address(reg));
    }
}
