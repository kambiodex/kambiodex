// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UniswapV3Deployer} from "./helpers/UniswapV3Deployer.sol";

/// @notice Implanta a KAMBIODEX (Uniswap v3 original) numa REDE DE TESTE.
///
/// Redes aceitas: Polygon Amoy (80002), BNB Chain Testnet (97) e a rede local de testes (31337).
/// Polygon (137) e BNB Chain (56) são BLOQUEADAS aqui de propósito: "nada em rede principal"
/// até auditoria + liberação jurídica (CLAUDE.md). Para a rede principal, criar um script novo,
/// revisado à parte.
///
/// Variáveis de ambiente (arquivo .env, fora do Git — NUNCA a chave privada):
///   OWNER_ADDRESS            carteira que será dona da Factory (obrigatória fora da rede local)
///   WRAPPED_NATIVE_ADDRESS   WPOL/WBNB da rede (opcional; se vazio, cria um token de teste)
///
/// A chave de quem paga o deploy NÃO fica neste arquivo: passa-se na linha de comando por
/// --account <nome> (carteira criptografada do Foundry) ou --ledger (carteira física).
contract Deploy is Script, UniswapV3Deployer {
    /// Só testnets. Qualquer outra rede faz o script parar.
    function networkName(uint256 chainId) public pure returns (string memory) {
        if (chainId == 80002) return "amoy";
        if (chainId == 97) return "bnb-testnet";
        if (chainId == 31337) return "local";
        revert("Rede nao permitida: so testnets (Amoy 80002, BNB Testnet 97)");
    }

    function wrappedTestnetNames(uint256 chainId) public pure returns (string memory, string memory) {
        if (chainId == 97) return ("Wrapped BNB (testnet)", "WBNB");
        return ("Wrapped POL (testnet)", "WPOL");
    }

    function run() external {
        string memory net = networkName(block.chainid); // bloqueia rede principal
        address owner = vm.envOr("OWNER_ADDRESS", address(0));
        address wrapped = vm.envOr("WRAPPED_NATIVE_ADDRESS", address(0));
        require(owner != address(0) || block.chainid == 31337, "Defina OWNER_ADDRESS no .env");

        console2.log("Rede:", net, "- chainId:", block.chainid);
        console2.log("Dono da Factory:", owner);

        vm.startBroadcast(); // quem paga vem de --account / --ledger

        if (wrapped == address(0)) {
            (string memory n, string memory s) = wrappedTestnetNames(block.chainid);
            wrapped = _create("WrappedNativeTestnet.sol:WrappedNativeTestnet", abi.encode(n, s));
            console2.log("Token embrulhado de TESTE criado:", wrapped);
        }
        Deployed memory d = deployAll(wrapped, owner);

        vm.stopBroadcast();

        console2.log("UniswapV3Factory:", d.factory);
        console2.log("NonfungibleTokenPositionDescriptor:", d.descriptor);
        console2.log("NonfungiblePositionManager:", d.positionManager);
        console2.log("SwapRouter:", d.router);
        console2.log("QuoterV2:", d.quoter);

        // Só grava o arquivo de endereços quando o envio é de verdade (--broadcast); simulação não grava.
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            string memory path = string.concat(vm.projectRoot(), "/../deployments/", net, ".json");
            vm.writeJson(addressesJson(d, owner), path);
            console2.log("Enderecos gravados em:", path);
        }
    }

    /// JSON com o que foi publicado, para deployments/<rede>.json.
    function addressesJson(Deployed memory d, address owner) public returns (string memory) {
        string memory k = "kambiodex_deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeAddress(k, "UniswapV3Factory", d.factory);
        vm.serializeAddress(k, "KambiodexPositionDescriptor", d.descriptor);
        vm.serializeAddress(k, "NonfungiblePositionManager", d.positionManager);
        vm.serializeAddress(k, "SwapRouter", d.router);
        vm.serializeAddress(k, "QuoterV2", d.quoter);
        vm.serializeAddress(k, "WrappedNative", d.wrappedNative);
        vm.serializeBytes32(k, "poolInitCodeHash", POOL_INIT_CODE_HASH);
        return vm.serializeAddress(k, "owner", owner);
    }
}
