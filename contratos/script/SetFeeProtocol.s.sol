// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IKambiodexPool} from "@kambiodex/core/interfaces/IKambiodexPool.sol";

/// @notice Liga a parte da exchange (1/6 da taxa) em pools já criadas: setFeeProtocol(6, 6).
///
/// Só o dono da Factory pode (se outra carteira tentar, a simulação já falha).
/// Variável de ambiente: POOL_ADDRESSES = endereços das pools separados por vírgula.
/// Quem paga/assina vem de --account <nome> ou --ledger, nunca de arquivo.
contract SetFeeProtocol is Script {
    uint8 constant FEE_PROTOCOL = 6; // 1/6

    function run() external {
        require(block.chainid == 80002 || block.chainid == 97 || block.chainid == 31337, "so testnets");
        address[] memory pools = vm.envAddress("POOL_ADDRESSES", ",");
        require(pools.length > 0, "Defina POOL_ADDRESSES");

        vm.startBroadcast();
        for (uint256 i = 0; i < pools.length; i++) {
            IKambiodexPool(pools[i]).setFeeProtocol(FEE_PROTOCOL, FEE_PROTOCOL);
            console2.log("setFeeProtocol(6,6) na pool:", pools[i]);
        }
        vm.stopBroadcast();
    }
}
