// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenRegistry.sol";

/// Uso (Amoy):  OWNER=0xSuaCarteira forge script script/DeployTokenRegistry.s.sol --rpc-url $AMOY_RPC --broadcast --private-key $PK
/// Na mainnet: OWNER = endereço da Safe.
contract DeployTokenRegistry is Script {
    function run() external {
        address owner_ = vm.envAddress("OWNER");
        vm.startBroadcast();
        TokenRegistry r = new TokenRegistry(owner_);
        vm.stopBroadcast();
        console.log("TokenRegistry:", address(r));
        console.log("Dono:", owner_);
    }
}
