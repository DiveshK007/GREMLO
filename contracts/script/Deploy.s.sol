// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CampaignVault} from "../src/CampaignVault.sol";

contract Deploy is Script {
    function run() external {
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        vm.startBroadcast();
        CampaignVault vault = new CampaignVault(operator);
        vm.stopBroadcast();
        console.log("CampaignVault:", address(vault));
    }
}
