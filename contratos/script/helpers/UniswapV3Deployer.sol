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

        // 2) Periphery (descriptor próprio da KAMBIODEX, sem proxy e sem biblioteca externa)
        d.descriptor = _create(
            "KambiodexPositionDescriptor.sol:KambiodexPositionDescriptor", abi.encode(wrappedNative, _nativeLabel())
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

    /// Rótulo da moeda nativa no desenho do NFT: BNB na BNB Chain (56/97); POL nas demais (Polygon e testes).
    function _nativeLabel() internal view returns (bytes32) {
        return (block.chainid == 56 || block.chainid == 97) ? bytes32("BNB") : bytes32("POL");
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
}
