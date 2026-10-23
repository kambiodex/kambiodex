// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Confere, SÓ POR LEITURA, os 5 contratos da KAMBIODEX publicados na Polygon PoS (chainId 137).
///
/// Não envia transação nenhuma: não usa broadcast, chave nem --account. Rode depois do deploy real, assim:
///   FACTORY_ADDRESS=0x... DESCRIPTOR_ADDRESS=0x... POSITION_MANAGER_ADDRESS=0x... ROUTER_ADDRESS=0x... \
///   QUOTER_ADDRESS=0x... forge script script/VerifyPolygon.s.sol --rpc-url <RPC da Polygon>
///
/// Imprime OK ou FALHOU por item e, no fim, o total. Se algum item falhar, o script termina com erro.
/// Os valores esperados (Trezor, WPOL, hash da pool) ficam FIXOS aqui, não vêm do ambiente.
/// Observação: o hash da pool é conferido (a) contra o bytecode compilado em out/, (b) dentro do código da
/// Factory (que contém o código da pool) e (c) embutido no código do Manager, do Router e do Quoter.
contract VerifyPolygon is Script {
    uint256 internal constant POLYGON_CHAIN_ID = 137;

    address internal constant OWNER = 0xcfaf6Cb6BF850B0088d675BEa655acf98017872E; // Trezor
    address internal constant WPOL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xefa1523a9c693954cc7417070043ba156e89adf78e52919814d859ef413bac17;

    uint256 internal failures;

    address internal factory;
    address internal descriptor;
    address internal manager;
    address internal router;
    address internal quoter;

    function run() external {
        factory = vm.envAddress("FACTORY_ADDRESS");
        descriptor = vm.envAddress("DESCRIPTOR_ADDRESS");
        manager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        router = vm.envAddress("ROUTER_ADDRESS");
        quoter = vm.envAddress("QUOTER_ADDRESS");

        console2.log("== Verificacao da KAMBIODEX na Polygon (somente leitura) ==");
        _checkCode();
        _checkFactory();
        _checkPeriphery();
        _checkPoolHash();

        console2.log("------------------------------------------");
        if (failures == 0) {
            console2.log("RESULTADO: TUDO OK");
        } else {
            console2.log("RESULTADO: FALHOU em itens:", failures);
        }
        require(failures == 0, "Verificacao FALHOU: veja os itens acima");
    }

    function _checkCode() internal {
        _item("rede e Polygon (chainId 137)", block.chainid == POLYGON_CHAIN_ID);
        _item("Factory tem codigo", factory.code.length > 0);
        _item("Descriptor tem codigo", descriptor.code.length > 0);
        _item("PositionManager tem codigo", manager.code.length > 0);
        _item("SwapRouter tem codigo", router.code.length > 0);
        _item("QuoterV2 tem codigo", quoter.code.length > 0);
        _item("WPOL tem codigo", WPOL.code.length > 0);
    }

    /// Dono da Factory = Trezor e as 4 faixas de taxa (taxa => espaçamento de ticks).
    function _checkFactory() internal {
        (bool okOwner, address owner) = _readAddress(factory, "owner()");
        _item("Factory.owner() == Trezor", okOwner && owner == OWNER);
        _item("faixa 0,01% (100) habilitada, espacamento 1", _spacing(100) == 1);
        _item("faixa 0,05% (500) habilitada, espacamento 10", _spacing(500) == 10);
        _item("faixa 0,30% (3000) habilitada, espacamento 60", _spacing(3000) == 60);
        _item("faixa 1% (10000) habilitada, espacamento 200", _spacing(10000) == 200);
    }

    /// Factory e WPOL de cada periférico + descriptor.
    function _checkPeriphery() internal {
        address[3] memory parts = [manager, router, quoter];
        string[3] memory names = ["PositionManager", "SwapRouter", "QuoterV2"];
        for (uint256 i = 0; i < 3; i++) {
            (bool okF, address f) = _readAddress(parts[i], "factory()");
            _item(string.concat(names[i], ".factory() == Factory"), okF && f == factory);
            (bool okW, address w) = _readAddress(parts[i], "WETH9()");
            _item(string.concat(names[i], ".WETH9() == WPOL"), okW && w == WPOL);
        }
        (bool okDw, address dw) = _readAddress(descriptor, "WETH9()");
        _item("Descriptor.WETH9() == WPOL", okDw && dw == WPOL);
        (bool okL, bytes32 label) = _readBytes32(descriptor, "nativeLabel()");
        _item("Descriptor.nativeLabel() == POL", okL && label == bytes32("POL"));

        // O descriptor é imutável dentro do Manager: o endereço dele precisa estar embutido no código do Manager.
        _item(
            "PositionManager aponta para o Descriptor (endereco embutido no codigo)",
            _contains(manager.code, abi.encodePacked(descriptor))
        );
    }

    function _checkPoolHash() internal {
        bytes memory poolCreation = vm.getCode("KambiodexPool.sol:KambiodexPool");
        _item("hash do bytecode compilado da pool == POOL_INIT_CODE_HASH", keccak256(poolCreation) == POOL_INIT_CODE_HASH);
        _item("Factory contem o codigo da pool compilado (mesmo hash)", _contains(factory.code, poolCreation));
        bytes memory h = abi.encodePacked(POOL_INIT_CODE_HASH);
        _item("PositionManager tem POOL_INIT_CODE_HASH no codigo", _contains(manager.code, h));
        _item("SwapRouter tem POOL_INIT_CODE_HASH no codigo", _contains(router.code, h));
        _item("QuoterV2 tem POOL_INIT_CODE_HASH no codigo", _contains(quoter.code, h));
    }

    function _item(string memory what, bool ok) internal {
        if (!ok) failures++;
        console2.log(string.concat(ok ? "OK      " : "FALHOU  ", what));
    }

    function _spacing(uint24 fee) internal view returns (int24 spacing) {
        (bool ok, bytes memory ret) = factory.staticcall(abi.encodeWithSignature("feeAmountTickSpacing(uint24)", fee));
        if (ok && ret.length == 32) spacing = abi.decode(ret, (int24));
    }

    function _readAddress(address target, string memory sig) internal view returns (bool ok, address value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(abi.encodeWithSignature(sig));
        if (ok && ret.length == 32) value = abi.decode(ret, (address));
        else ok = false;
    }

    function _readBytes32(address target, string memory sig) internal view returns (bool ok, bytes32 value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(abi.encodeWithSignature(sig));
        if (ok && ret.length == 32) value = abi.decode(ret, (bytes32));
        else ok = false;
    }

    /// `needle` aparece em algum ponto de `hay`?
    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0 || needle.length > hay.length) return false;
        bytes1 first = needle[0];
        for (uint256 i = 0; i + needle.length <= hay.length; i++) {
            if (hay[i] != first) continue;
            bool match_ = true;
            for (uint256 j = 1; j < needle.length; j++) {
                if (hay[i + j] != needle[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }
}
