// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "../helpers/MockERC20.sol";
import {INPM, ISwapRouterLike, IQuoterV2Like} from "../helpers/IPeriphery.sol";

/// @notice Simulação 100% local sobre os contratos JÁ PUBLICADOS na Polygon Amoy (chainId 80002).
///         Usa um "fork": o Foundry copia o estado da rede para a memória e roda tudo ali.
///         Nada é enviado à rede real: sem chave, sem keystore, sem --broadcast e sem gás.
///         O "dono" da Factory é imitado com vm.prank, que só funciona dentro do fork.
contract KambiodexAmoyForkTest is Test {
    string constant RPC = "https://polygon-amoy-bor-rpc.publicnode.com";

    address constant FACTORY = 0x4E98D1d960f6198fA4dAA79e2e013f710e021cd3;
    address constant NPM = 0x990333bc228BC2B7dFF4c0D9A1959d77544CBdFa;
    address constant ROUTER = 0xfCda92d9dd56178e6F0BD33e73d185dcfF3f8218;
    address constant QUOTER = 0xbBA86ce67F5F96Bf155af3A71CE47c52D7B3492A;
    address constant OWNER = 0xc6BB717dF718F68bd6727FC6fd7974206D7EB90c;

    uint24 constant FEE = 3000;
    uint160 constant PRICE_1 = 2 ** 96; // preço 1:1
    int24 constant FULL_TICK = 887220; // maior múltiplo de 60 dentro do limite (faixa completa)
    uint128 constant U128_MAX = type(uint128).max;

    IUniswapV3Factory factory = IUniswapV3Factory(FACTORY);
    INPM npm = INPM(NPM);
    ISwapRouterLike router = ISwapRouterLike(ROUTER);
    IQuoterV2Like quoter = IQuoterV2Like(QUOTER);

    MockERC20 t0;
    MockERC20 t1;
    IUniswapV3Pool pool;
    address lp = makeAddr("lp");
    address trader = makeAddr("trader");
    address treasury = makeAddr("treasury");
    uint256 tokenId;

    function setUp() public {
        vm.createSelectFork(RPC);
        assertEq(block.chainid, 80002, "nao e a Amoy");

        // (2) dois ERC20 de teste, criados só dentro do fork (ordenados como o v3 exige)
        MockERC20 a = new MockERC20("Token A", "AAA", 18);
        MockERC20 b = new MockERC20("Token B", "BBB", 18);
        (t0, t1) = address(a) < address(b) ? (a, b) : (b, a);

        address[2] memory people = [lp, trader];
        for (uint256 i = 0; i < 2; i++) {
            t0.mint(people[i], 1e30);
            t1.mint(people[i], 1e30);
            vm.startPrank(people[i]);
            t0.approve(NPM, type(uint256).max);
            t1.approve(NPM, type(uint256).max);
            t0.approve(ROUTER, type(uint256).max);
            t1.approve(ROUTER, type(uint256).max);
            vm.stopPrank();
        }

        // cria + inicializa a pool (fee 3000, preço 1:1) e adiciona liquidez em faixa completa
        pool = IUniswapV3Pool(npm.createAndInitializePoolIfNecessary(address(t0), address(t1), FEE, PRICE_1));
        vm.prank(lp);
        (tokenId,,,) = npm.mint(
            INPM.MintParams({
                token0: address(t0),
                token1: address(t1),
                fee: FEE,
                tickLower: -FULL_TICK,
                tickUpper: FULL_TICK,
                amount0Desired: 1_000_000e18,
                amount1Desired: 1_000_000e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: lp,
                deadline: block.timestamp + 1 hours
            })
        );
    }

    function _swap(MockERC20 tin, MockERC20 tout, uint256 amountIn) internal returns (uint256 out) {
        vm.prank(trader);
        out = router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams({
                tokenIn: address(tin),
                tokenOut: address(tout),
                fee: FEE,
                recipient: trader,
                deadline: block.timestamp + 1 hours,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // (1) estado dos contratos publicados
    function test_1_published_state() public view {
        assertEq(factory.owner(), OWNER, "dono da Factory");
        assertEq(factory.feeAmountTickSpacing(100), 1, "faixa 0,01% habilitada");
        assertEq(factory.feeAmountTickSpacing(500), 10, "faixa 0,05%");
        assertEq(factory.feeAmountTickSpacing(3000), 60, "faixa 0,30%");
        assertEq(factory.feeAmountTickSpacing(10000), 200, "faixa 1%");
        assertEq(npm.factory(), FACTORY, "NPM aponta para a Factory publicada");
    }

    // (2) pool criada, preço inicializado e liquidez adicionada
    function test_2_pool_and_liquidity() public view {
        assertEq(factory.getPool(address(t0), address(t1), FEE), address(pool), "pool registrada");
        (uint160 sqrtP,,,,,,) = pool.slot0();
        assertEq(sqrtP, PRICE_1, "preco inicial");
        assertGt(pool.liquidity(), 0, "liquidez ativa");
        assertEq(npm.ownerOf(tokenId), lp, "NFT da posicao");
    }

    // (3) swap pelo SwapRouter confere com a cotacao do QuoterV2
    function test_3_swap_matches_quoter() public {
        uint256 amountIn = 1_000e18;
        (uint256 quoted,,,) = quoter.quoteExactInputSingle(
            IQuoterV2Like.QuoteExactInputSingleParams({
                tokenIn: address(t0),
                tokenOut: address(t1),
                amountIn: amountIn,
                fee: FEE,
                sqrtPriceLimitX96: 0
            })
        );
        uint256 before1 = t1.balanceOf(trader);
        uint256 out = _swap(t0, t1, amountIn);
        assertEq(out, quoted, "swap diferente da cotacao");
        assertEq(t1.balanceOf(trader) - before1, out, "saldo recebido");
        assertLt(out, amountIn, "tem de pagar a taxa");
    }

    // (4) e (5) taxa do protocolo: setFeeProtocol(6,6) -> ~1/6 das taxas; collectProtocol
    function test_4_5_protocol_fee_is_one_sixth_and_collectable() public {
        // antes de ligar: nada vai para o protocolo, mesmo com trocas
        _swap(t0, t1, 1_000e18);
        (uint128 p0, uint128 p1) = pool.protocolFees();
        assertEq(p0, 0);
        assertEq(p1, 0);

        // só o dono liga (imitado dentro do fork)
        vm.expectRevert();
        pool.setFeeProtocol(6, 6);
        vm.prank(OWNER);
        pool.setFeeProtocol(6, 6);
        (,,,,, uint8 feeProtocol,) = pool.slot0();
        assertEq(feeProtocol, (6 << 4) | 6, "feeProtocol = 6,6");

        // novas trocas nos dois sentidos
        uint256 in0;
        uint256 in1;
        for (uint256 i = 0; i < 5; i++) {
            _swap(t0, t1, 10_000e18);
            in0 += 10_000e18;
            uint256 back = _swap(t1, t0, 8_000e18);
            back; // só para consumir o retorno
            in1 += 8_000e18;
        }

        // taxa total = 0,30% do que entrou; protocolo = 1/6 disso (= 0,05%)
        (p0, p1) = pool.protocolFees();
        assertGt(p0, 0);
        assertGt(p1, 0);
        assertApproxEqRel(uint256(p0), (in0 * FEE / 1e6) / 6, 1e15, "token0: ~1/6 da taxa");
        assertApproxEqRel(uint256(p1), (in1 * FEE / 1e6) / 6, 1e15, "token1: ~1/6 da taxa");

        // quem não é dono não coleta
        vm.expectRevert();
        pool.collectProtocol(treasury, U128_MAX, U128_MAX);

        // o dono coleta (o v3 deixa 1 wei na pool de propósito)
        vm.prank(OWNER);
        (uint128 got0, uint128 got1) = pool.collectProtocol(treasury, U128_MAX, U128_MAX);
        assertEq(got0, p0 - 1);
        assertEq(got1, p1 - 1);
        assertEq(t0.balanceOf(treasury), got0);
        assertEq(t1.balanceOf(treasury), got1);
        (uint128 r0, uint128 r1) = pool.protocolFees();
        assertEq(r0, 1);
        assertEq(r1, 1);
    }

    // (6) nome/símbolo do NFT da posição
    function test_6_nft_name() public view {
        assertEq(npm.name(), "KAMBIODEX V3 Positions");
        assertEq(npm.symbol(), "KBX-V3-POS");
    }
}
