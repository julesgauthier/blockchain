// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import {SimpleVotingSystem} from "../src/SimpleVotingSystem2.sol";

contract DeploySimpleStorage is Script {
    function run() external returns (SimpleVotingSystem) {
        // start and stop broadcast indicates that everything inside means that we are going to call an RPC Node
        vm.startBroadcast();
        SimpleVotingSystem simpleVotingSystem = new SimpleVotingSystem();
        vm.stopBroadcast();
        return simpleVotingSystem;
    }
}
