// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IPeripheryImmutableState {
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

/// @notice Monta, em ordem, todos os contratos da KAMBIODEX (Uniswap v3 original, sem proxy).
/// @dev Os contratos do Uniswap são Solidity 0.7.6 e este arquivo é 0.8, por isso são criados a
///      partir do código já compilado (pasta out/). Usado pelo script de deploy E pelos testes.
abstract contract UniswapV3Deployer is CommonBase {
    struct Deployed {
        address factory;
        address nftDescriptorLib;
        address descriptor;
        address positionManager;
        address router;
        address quoter;
        address wrappedNative;
    }

    /// Hash do código da pool que o periphery espera (PoolAddress.POOL_INIT_CODE_HASH, igual ao oficial).
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// Faixas de taxa (CLAUDE.md): 0,01% 0,05% 0,30% 1%. A de 0,01% não vem habilitada no original.
    uint24 internal constant FEE_100 = 100;
    int24 internal constant SPACING_100 = 1;

    /// @param wrappedNative WPOL (Polygon) / WBNB (BNB Chain). Nunca inventar: vem de fora.
    /// @param finalOwner novo dono da Factory; address(0) = continua com quem implantou.
    function deployAll(address wrappedNative, address finalOwner) public returns (Deployed memory d) {
        require(wrappedNative != address(0), "wrappedNative vazio");
        d.wrappedNative = wrappedNative;

        // 1) Núcleo
        d.factory = _create("UniswapV3Factory.sol:UniswapV3Factory", "");
        IUniswapV3Factory(d.factory).enableFeeAmount(FEE_100, SPACING_100); // 0,01% (só o dono pode)

        // 2) Periphery (descriptor sem proxy, conforme CLAUDE.md)
        d.nftDescriptorLib = _create("NFTDescriptor.sol:NFTDescriptor", "");
        d.descriptor = _deployLinked(
            "NonfungibleTokenPositionDescriptor", d.nftDescriptorLib, abi.encode(wrappedNative)
        );
        d.positionManager = _create(
            "NonfungiblePositionManager.sol:NonfungiblePositionManager",
            abi.encode(d.factory, wrappedNative, d.descriptor)
        );
        d.router = _create("SwapRouter.sol:SwapRouter", abi.encode(d.factory, wrappedNative));
        d.quoter = _create("QuoterV2.sol:QuoterV2", abi.encode(d.factory, wrappedNative));

        // 3) Por último, passa a propriedade da Factory (depois de habilitar a faixa de 0,01%)
        if (finalOwner != address(0)) IUniswapV3Factory(d.factory).setOwner(finalOwner);

        _check(d, finalOwner);
    }

    /// Confere o resultado; se algo estiver errado, o script inteiro falha.
    function _check(Deployed memory d, address finalOwner) internal view {
        // Se as opções de compilação mudarem, o periphery calcularia endereços de pool errados.
        require(keccak256(vm.getCode("UniswapV3Pool.sol:UniswapV3Pool")) == POOL_INIT_CODE_HASH, "hash da pool mudou");

        IUniswapV3Factory f = IUniswapV3Factory(d.factory);
        require(f.feeAmountTickSpacing(100) == 1, "faixa 0,01% desligada");
        require(f.feeAmountTickSpacing(500) == 10, "faixa 0,05% errada");
        require(f.feeAmountTickSpacing(3000) == 60, "faixa 0,30% errada");
        require(f.feeAmountTickSpacing(10000) == 200, "faixa 1% errada");
        if (finalOwner != address(0)) require(f.owner() == finalOwner, "dono errado");

        address[3] memory parts = [d.positionManager, d.router, d.quoter];
        for (uint256 i = 0; i < 3; i++) {
            require(IPeripheryImmutableState(parts[i]).factory() == d.factory, "factory errada");
            require(IPeripheryImmutableState(parts[i]).WETH9() == d.wrappedNative, "WETH9 errado");
        }
        require(IPeripheryImmutableState(d.descriptor).WETH9() == d.wrappedNative, "descriptor errado");
    }

    // ------------------------------------------------------------ ligação de biblioteca

    /// @dev O descriptor usa a biblioteca NFTDescriptor "por fora". O compilador deixa no código
    ///      um marcador `__$...$__` (40 caracteres) no lugar do endereço da biblioteca; aqui
    ///      trocamos o marcador pelo endereço real e criamos o contrato.
    function _deployLinked(string memory name, address lib, bytes memory ctorArgs) internal returns (address addr) {
        string memory path = string.concat(vm.projectRoot(), "/out/", name, ".sol/", name, ".json");
        string memory code = vm.parseJsonString(vm.readFile(path), ".bytecode.object");
        bytes memory initCode = abi.encodePacked(vm.parseBytes(_link(code, lib)), ctorArgs);
        addr = _createRaw(initCode);
    }

    /// Cria um contrato a partir do artefato compilado (out/) + argumentos do construtor.
    function _create(string memory artifact, bytes memory ctorArgs) internal returns (address) {
        return _createRaw(abi.encodePacked(vm.getCode(artifact), ctorArgs));
    }

    function _createRaw(bytes memory initCode) internal returns (address addr) {
        assembly {
            addr := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(addr != address(0), "falha ao criar contrato");
    }

    function _link(string memory code, address lib) internal pure returns (string memory) {
        bytes memory b = bytes(code);
        bytes memory h = "0123456789abcdef";
        bytes memory libHex = new bytes(40);
        for (uint256 k = 0; k < 20; k++) {
            uint8 v = uint8(uint160(lib) >> (8 * (19 - k)));
            libHex[2 * k] = h[v >> 4];
            libHex[2 * k + 1] = h[v & 0x0f];
        }
        uint256 replaced;
        for (uint256 i = 0; i + 40 <= b.length; i++) {
            if (b[i] == "_" && b[i + 1] == "_" && b[i + 2] == "$") {
                for (uint256 j = 0; j < 40; j++) {
                    b[i + j] = libHex[j];
                }
                i += 39;
                replaced++;
            }
        }
        require(replaced > 0, "nenhum marcador de biblioteca");
        return string(b);
    }
}
