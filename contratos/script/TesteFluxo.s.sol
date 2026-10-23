// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MockERC20} from "../test/helpers/MockERC20.sol";
import {INPM, ISwapRouterLike} from "../test/helpers/IPeriphery.sol";

interface IFactoryLike {
    function owner() external view returns (address);
    function getPool(address a, address b, uint24 fee) external view returns (address);
}

interface IPoolLike {
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;
    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, uint8 feeProtocol, bool);
    function liquidity() external view returns (uint128);
}

/// @notice Teste REAL do fluxo completo na Polygon Amoy (80002), com os contratos já publicados
///         (endereços lidos de deployments/amoy-kambiodex-v1.json, o arquivo do deploy novo feito por Deploy.s.sol;
///         o amoy.json antigo é do deploy anterior à renomeação e NÃO é usado).
///
/// Passos: cria 2 tokens de teste -> aprova NFT manager e roteador -> cria/inicializa a pool
/// (taxa 0,30%, preço 1:1) -> adiciona liquidez (faixa completa) -> troca pequena -> setFeeProtocol(6,6)
/// -> trocas nos dois sentidos -> confere protocolFees e faz collectProtocol para a carteira do dono.
///
/// SEM chave aqui: quem assina e paga vem da linha de comando (--account <nome> ou --ledger).
/// Só roda na Amoy. Sem --broadcast é apenas simulação (nada é enviado à rede).
contract TesteFluxo is Script {
    using stdJson for string;

    uint24 constant FEE = 3000;
    int24 constant TICK_MIN = -887220; // múltiplo de 60 (faixa completa)
    int24 constant TICK_MAX = 887220;
    uint160 constant PRICE_1_1 = 79228162514264337593543950336; // sqrt(1) * 2^96

    uint256 constant SALDO = 1_000e18; // por token
    uint256 constant LIQUIDEZ = 100e18; // por token
    uint256 constant SWAP_INICIAL = 1e18;
    uint256 constant SWAP = 5e18;

    struct Ctx {
        address owner;
        INPM npm;
        ISwapRouterLike router;
        address pool;
        address t0;
        address t1;
    }

    function run() external {
        require(block.chainid == 80002, "So na Polygon Amoy (80002)");

        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/../deployments/amoy-kambiodex-v1.json"));
        address factory = json.readAddress(".KambiodexFactory");
        Ctx memory c;
        c.npm = INPM(json.readAddress(".NonfungiblePositionManager"));
        c.router = ISwapRouterLike(json.readAddress(".SwapRouter"));
        c.owner = json.readAddress(".owner");
        require(IFactoryLike(factory).owner() == c.owner, "Dono da Factory diferente do JSON");

        vm.startBroadcast(); // assinatura vem de --account / --ledger (ou --sender na simulacao)

        // (1) dois ERC20 de teste, com saldo para o dono
        MockERC20 a = new MockERC20("KDX Teste A", "KTA", 18);
        MockERC20 b = new MockERC20("KDX Teste B", "KTB", 18);
        a.mint(c.owner, SALDO);
        b.mint(c.owner, SALDO);
        (c.t0, c.t1) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));

        // (2) aprovações
        MockERC20(c.t0).approve(address(c.npm), type(uint256).max);
        MockERC20(c.t1).approve(address(c.npm), type(uint256).max);
        MockERC20(c.t0).approve(address(c.router), type(uint256).max);
        MockERC20(c.t1).approve(address(c.router), type(uint256).max);

        // (3) cria e inicializa a pool (1:1) e adiciona liquidez em faixa completa
        c.pool = c.npm.createAndInitializePoolIfNecessary(c.t0, c.t1, FEE, PRICE_1_1);
        require(c.pool == IFactoryLike(factory).getPool(c.t0, c.t1, FEE), "Pool inesperada");
        (uint256 tokenId, uint128 liq, uint256 dep0, uint256 dep1) = c.npm.mint(
            INPM.MintParams({
                token0: c.t0,
                token1: c.t1,
                fee: FEE,
                tickLower: TICK_MIN,
                tickUpper: TICK_MAX,
                amount0Desired: LIQUIDEZ,
                amount1Desired: LIQUIDEZ,
                amount0Min: 0,
                amount1Min: 0,
                recipient: c.owner,
                deadline: block.timestamp + 1200
            })
        );

        // (4) troca pequena (token0 -> token1), ainda sem taxa do protocolo
        uint256 out1 = _swap(c, c.t0, c.t1, SWAP_INICIAL);
        (uint128 p0, uint128 p1) = IPoolLike(c.pool).protocolFees();
        require(p0 == 0 && p1 == 0, "Nao deveria haver taxa do protocolo antes do setFeeProtocol");

        // (5) liga a parte da exchange: 1/6 da taxa
        IPoolLike(c.pool).setFeeProtocol(6, 6);
        (,,,,, uint8 fp,) = IPoolLike(c.pool).slot0();
        require(fp == (6 << 4) | 6, "setFeeProtocol nao ficou 6,6");

        // (6) trocas nos dois sentidos
        _swap(c, c.t0, c.t1, SWAP);
        _swap(c, c.t1, c.t0, SWAP);
        _swap(c, c.t0, c.t1, SWAP);
        _swap(c, c.t1, c.t0, SWAP);

        // (7) confere as taxas do protocolo e coleta para a carteira do dono
        (p0, p1) = IPoolLike(c.pool).protocolFees();
        require(p0 > 0 && p1 > 0, "protocolFees deveria ser > 0 nos dois tokens");
        (uint128 got0, uint128 got1) = IPoolLike(c.pool).collectProtocol(c.owner, type(uint128).max, type(uint128).max);

        vm.stopBroadcast();

        // (8) relatório
        console2.log("=== TESTE DE FLUXO - Polygon Amoy ===");
        console2.log("Dono (carteira):", c.owner);
        console2.log("Token A (KTA):", address(a));
        console2.log("Token B (KTB):", address(b));
        console2.log("token0 da pool:", c.t0);
        console2.log("token1 da pool:", c.t1);
        console2.log("Pool (taxa 0,30%):", c.pool);
        console2.log("NFT da posicao (tokenId):", tokenId);
        console2.log("Liquidez adicionada:", uint256(liq));
        console2.log("Depositado token0 (wei):", dep0);
        console2.log("Depositado token1 (wei):", dep1);
        console2.log("Troca inicial: entrou token0 (wei):", SWAP_INICIAL);
        console2.log("Troca inicial: saiu token1 (wei):", out1);
        console2.log("protocolFees token0 (wei):", uint256(p0));
        console2.log("protocolFees token1 (wei):", uint256(p1));
        console2.log("Coletado pela exchange token0 (wei):", uint256(got0));
        console2.log("Coletado pela exchange token1 (wei):", uint256(got1));
    }

    function _swap(Ctx memory c, address tin, address tout, uint256 amountIn) internal returns (uint256) {
        return c.router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams({
                tokenIn: tin,
                tokenOut: tout,
                fee: FEE,
                recipient: c.owner,
                deadline: block.timestamp + 1200,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
