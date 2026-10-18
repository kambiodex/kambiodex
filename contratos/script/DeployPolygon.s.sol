// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UniswapV3Deployer} from "./helpers/UniswapV3Deployer.sol";

interface IERC20Meta {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @notice Implanta a KAMBIODEX na POLYGON PoS (chainId 137) — REDE PRINCIPAL, dinheiro de verdade.
///
/// NÃO rodar sem: auditoria concluída + liberação jurídica (CLAUDE.md, "Etapa atual", item 5).
///
/// O que este script faz (e só isso):
///   1. confere que a rede é a Polygon (137) e que o WPOL fixo existe e é mesmo um WPOL (símbolo e 18 casas);
///   2. publica Factory, descriptor, NonfungiblePositionManager, SwapRouter e QuoterV2;
///   3. habilita a faixa de 0,01% (as outras três já vêm no Uniswap v3);
///   4. passa a propriedade da Factory (setOwner) para OWNER_ADDRESS e confere tudo (_check);
///   5. só com --broadcast, grava deployments/polygon.json.
/// Nunca cria token de teste: o token embrulhado é o WPOL oficial, fixo no código.
///
/// Variável de ambiente (.env, fora do Git):
///   OWNER_ADDRESS   carteira que será dona da Factory (OBRIGATÓRIA, diferente de zero e diferente do deployer)
///
/// Quem paga o deploy (Deployer) NÃO fica aqui: vai na linha de comando, por --account <nome> ou --ledger.
/// Simulação (sem --broadcast) não envia nada nem grava arquivo.
contract DeployPolygon is Script, UniswapV3Deployer {
    uint256 internal constant POLYGON_CHAIN_ID = 137;

    /// WPOL (Wrapped POL, ex-WMATIC) na Polygon PoS. Confira em polygonscan.com antes de qualquer envio real.
    address internal constant WPOL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    /// Endereço de quem assina quando nenhuma conta foi informada (padrão do Foundry): nunca aceitar.
    address internal constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    function run() external {
        require(block.chainid == POLYGON_CHAIN_ID, "So Polygon PoS (chainId 137)");

        address owner = vm.envOr("OWNER_ADDRESS", address(0));
        require(owner != address(0), "Defina OWNER_ADDRESS (carteira dona da Factory)");

        string memory path = string.concat(vm.projectRoot(), "/../deployments/polygon.json");
        require(!vm.exists(path), "deployments/polygon.json ja existe: nao publicar duas vezes");

        _validateWpol();

        vm.startBroadcast(); // quem paga vem de --account / --ledger
        (, address deployer,) = vm.readCallers();
        // (Nos testes automatizados não há --account: lá a conta padrão do Foundry é aceita.)
        if (!vm.isContext(VmSafe.ForgeContext.TestGroup)) {
            require(deployer != address(0) && deployer != FOUNDRY_DEFAULT_SENDER, "Informe --account ou --ledger");
        }
        require(deployer != owner, "OWNER_ADDRESS nao pode ser o Deployer");

        console2.log("Rede: polygon - chainId:", block.chainid);
        console2.log("Deployer (quem assina):", deployer);
        console2.log("Dono da Factory (OWNER_ADDRESS):", owner);

        // deployAll: Factory, faixa 0,01%, descriptor, NPM, SwapRouter, QuoterV2, setOwner(owner) e _check.
        Deployed memory d = deployAll(WPOL, owner);

        vm.stopBroadcast();

        console2.log("UniswapV3Factory:", d.factory);
        console2.log("KambiodexPositionDescriptor:", d.descriptor);
        console2.log("NonfungiblePositionManager:", d.positionManager);
        console2.log("SwapRouter:", d.router);
        console2.log("QuoterV2:", d.quoter);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            vm.writeJson(addressesJson(d, owner), path);
            console2.log("Enderecos gravados em:", path);
        }
    }

    /// O WPOL fixo tem de existir na rede e se comportar como WPOL. Se não, o script para antes de gastar gás.
    function _validateWpol() internal view {
        require(WPOL.code.length > 0, "WPOL sem codigo nesta rede");
        require(keccak256(bytes(IERC20Meta(WPOL).symbol())) == keccak256("WPOL"), "WPOL: simbolo inesperado");
        require(IERC20Meta(WPOL).decimals() == 18, "WPOL: decimals diferente de 18");
    }

    /// JSON com o que foi publicado, para deployments/polygon.json.
    function addressesJson(Deployed memory d, address owner) public returns (string memory) {
        string memory k = "kambiodex_polygon_deployment";
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
