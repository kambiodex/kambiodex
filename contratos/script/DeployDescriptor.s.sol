// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

interface IFactoryLike {
    function owner() external view returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

interface IPeripheryLike {
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

interface IDescriptorLike {
    function WETH9() external view returns (address);
    function nativeLabel() external view returns (bytes32);
}

interface IErc20Like {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @custom:status OBSOLETO para o deploy novo da Amoy (código renomeado, out/2026). O deploy novo é feito por inteiro
///         pelo Deploy.s.sol (grava deployments/amoy-kambiodex-v1.json), com Factory, descriptor e periphery novos.
///         Este script reaproveita a Factory ANTIGA (deployments/amoy.json, hash da pool antigo) e por isso a trava
///         de hash abaixo o impede de rodar. Fica só como histórico do deploy anterior; NÃO usar.
///
/// @notice Publica SÓ o KambiodexPositionDescriptor e um NonfungiblePositionManager novo na POLYGON AMOY (80002),
///         reaproveitando a Factory e o token embrulhado (WPOL) já publicados em deployments/amoy.json.
///         SwapRouter e QuoterV2 não mudam (não dependem do descriptor).
///
/// Por que o Manager também: ele guarda o endereço do descriptor de forma imutável.
/// O Manager novo começa SEM posições; as posições do Manager antigo continuam no Manager antigo.
///
/// Só a Amoy. Qualquer outra rede faz o script parar.
/// O resultado vai para deployments/amoy-descriptor-v2.json (o amoy.json e o amoy-descriptor.json do deploy anterior NUNCA são alterados) e só é gravado
/// em envio de verdade (--broadcast); simulação não grava nada. Se o arquivo já existir, o script para.
///
/// Uso (simulação, não gasta nada):  forge script script/DeployDescriptor.s.sol --rpc-url amoy
/// A chave de quem paga NÃO fica aqui: no envio real passa-se --account <nome> ou --ledger.
contract DeployDescriptor is Script {
    uint256 internal constant AMOY_CHAIN_ID = 80002;
    bytes32 internal constant NATIVE_LABEL = bytes32("POL");
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xefa1523a9c693954cc7417070043ba156e89adf78e52919814d859ef413bac17;

    string internal constant IN_FILE = "/../deployments/amoy.json";
    string internal constant OUT_FILE = "/../deployments/amoy-descriptor-v2.json";
    // Commit do código do descriptor publicado por este script (faixa completa mostra FULL RANGE).
    string internal constant SOURCE_COMMIT = "cb3cf9e";

    function run() external {
        require(block.chainid == AMOY_CHAIN_ID, "So Polygon Amoy (chainId 80002)");

        string memory inPath = string.concat(vm.projectRoot(), IN_FILE);
        string memory outPath = string.concat(vm.projectRoot(), OUT_FILE);
        require(!vm.exists(outPath), "amoy-descriptor-v2.json ja existe: nao sobrescrevo");

        string memory j = vm.readFile(inPath);
        require(vm.parseJsonUint(j, ".chainId") == AMOY_CHAIN_ID, "amoy.json nao e da Amoy");
        require(vm.parseJsonBytes32(j, ".poolInitCodeHash") == POOL_INIT_CODE_HASH, "hash da pool diferente");
        address factory = vm.parseJsonAddress(j, ".KambiodexFactory");
        address wrapped = vm.parseJsonAddress(j, ".WrappedNative");

        _checkExisting(factory, wrapped);

        console2.log("Rede: amoy - chainId:", block.chainid);
        console2.log("Factory (reaproveitada):", factory);
        console2.log("WPOL (reaproveitado):", wrapped);

        vm.startBroadcast(); // quem paga vem de --account / --ledger
        address descriptor = _create(
            "KambiodexPositionDescriptor.sol:KambiodexPositionDescriptor", abi.encode(wrapped, NATIVE_LABEL)
        );
        address manager = _create(
            "NonfungiblePositionManager.sol:NonfungiblePositionManager", abi.encode(factory, wrapped, descriptor)
        );
        vm.stopBroadcast();

        _checkNew(descriptor, manager, factory, wrapped);

        console2.log("KambiodexPositionDescriptor (novo):", descriptor);
        console2.log("NonfungiblePositionManager (novo):", manager);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            string memory k = "kambiodex_descriptor_deployment";
            vm.serializeUint(k, "chainId", block.chainid);
            vm.serializeAddress(k, "KambiodexFactory", factory);
            vm.serializeAddress(k, "WrappedNative", wrapped);
            vm.serializeAddress(k, "KambiodexPositionDescriptor", descriptor);
            vm.serializeString(k, "descriptorSourceCommit", SOURCE_COMMIT);
            vm.serializeBytes32(k, "nativeLabel", NATIVE_LABEL);
            vm.serializeBytes32(k, "poolInitCodeHash", POOL_INIT_CODE_HASH);
            string memory out = vm.serializeAddress(k, "NonfungiblePositionManager", manager);
            vm.writeJson(out, outPath);
            console2.log("Enderecos gravados em:", outPath);
        }
    }

    /// A Factory e o WPOL de amoy.json precisam existir na rede e se comportar como esperado.
    function _checkExisting(address factory, address wrapped) internal view {
        require(factory.code.length > 0, "Factory sem codigo nesta rede");
        require(wrapped.code.length > 0, "WPOL sem codigo nesta rede");
        IFactoryLike f = IFactoryLike(factory);
        require(f.feeAmountTickSpacing(3000) == 60, "Factory: faixa 0,30% errada");
        require(f.feeAmountTickSpacing(100) == 1, "Factory: faixa 0,01% desligada");
        require(keccak256(bytes(IErc20Like(wrapped).symbol())) == keccak256("WPOL"), "WPOL: simbolo inesperado");
        require(IErc20Like(wrapped).decimals() == 18, "WPOL: decimals diferente de 18");
    }

    /// Confere o que acabou de ser criado; se algo estiver errado, o script falha.
    function _checkNew(address descriptor, address manager, address factory, address wrapped) internal view {
        require(descriptor.code.length > 0 && manager.code.length > 0, "contrato sem codigo");
        require(IDescriptorLike(descriptor).WETH9() == wrapped, "descriptor: WETH9 errado");
        require(IDescriptorLike(descriptor).nativeLabel() == NATIVE_LABEL, "descriptor: rotulo errado");
        require(IPeripheryLike(manager).factory() == factory, "manager: factory errada");
        require(IPeripheryLike(manager).WETH9() == wrapped, "manager: WETH9 errado");
    }

    /// Cria um contrato a partir do artefato compilado (out/) + argumentos do construtor.
    function _create(string memory artifact, bytes memory ctorArgs) internal returns (address addr) {
        bytes memory initCode = abi.encodePacked(vm.getCode(artifact), ctorArgs);
        assembly {
            addr := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(addr != address(0), "falha ao criar contrato");
    }
}
