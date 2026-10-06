// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {PoolActor} from "./helpers/PoolActor.sol";

/// @notice Etapa 1 do CLAUDE.md, parte "núcleo" (v3-core): faixas de taxa, posições, trocas,
///         collect e taxa do protocolo. Os contratos do Uniswap (Solidity 0.7.6) são criados a
///         partir do código já compilado (deployCode); estes testes usam Solidity 0.8.
contract CoreTest is Test {
    uint160 constant PRICE_1 = 2 ** 96; // sqrtPriceX96 de preço 1 (tick 0)
    uint160 constant MIN_LIMIT = 4295128740; // MIN_SQRT_RATIO + 1
    uint160 constant MAX_LIMIT = 1461446703485210103287273052203988822378723970341; // MAX_SQRT_RATIO - 1
    int24 constant MAX_TICK = 887272;
    uint128 constant L = 1e21;

    IUniswapV3Factory factory;
    MockERC20 token0;
    MockERC20 token1;
    PoolActor lp;
    PoolActor trader;

    function setUp() public {
        // O dono da Factory é quem a cria: este contrato de teste.
        factory = IUniswapV3Factory(deployCode("UniswapV3Factory.sol:UniswapV3Factory"));

        MockERC20 a = new MockERC20("Token A", "AAA", 18);
        MockERC20 b = new MockERC20("Token B", "BBB", 18);
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);

        lp = new PoolActor();
        trader = new PoolActor();
        token0.mint(address(lp), 1e30);
        token1.mint(address(lp), 1e30);
        token0.mint(address(trader), 1e30);
        token1.mint(address(trader), 1e30);
    }

    // ---------------------------------------------------------------- helpers

    function _newPool(uint24 fee) internal returns (IUniswapV3Pool pool) {
        pool = IUniswapV3Pool(factory.createPool(address(token0), address(token1), fee));
        pool.initialize(PRICE_1);
    }

    function _spacing(uint24 fee) internal view returns (int24) {
        return factory.feeAmountTickSpacing(fee);
    }

    function _fullRange(uint24 fee) internal view returns (int24 lower, int24 upper) {
        int24 s = _spacing(fee);
        upper = (MAX_TICK / s) * s;
        lower = -upper;
    }

    function _tick(IUniswapV3Pool pool) internal view returns (int24 tick) {
        (, tick,,,,,) = pool.slot0();
    }

    function _sqrtPrice(IUniswapV3Pool pool) internal view returns (uint160 p) {
        (p,,,,,,) = pool.slot0();
    }

    // ------------------------------------------------- faixas de taxa (fee tiers)

    function test_defaultFeeTiers() public view {
        // A Factory original já vem com 0,05%, 0,30% e 1%. A de 0,01% NÃO vem habilitada.
        assertEq(factory.feeAmountTickSpacing(500), 10);
        assertEq(factory.feeAmountTickSpacing(3000), 60);
        assertEq(factory.feeAmountTickSpacing(10000), 200);
        assertEq(factory.feeAmountTickSpacing(100), 0);
        assertEq(factory.owner(), address(this));
    }

    function test_createPool_failsForTierNotEnabled() public {
        vm.expectRevert();
        factory.createPool(address(token0), address(token1), 100);
    }

    function test_enableFeeTier100_onlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        factory.enableFeeAmount(100, 1);

        factory.enableFeeAmount(100, 1);
        assertEq(factory.feeAmountTickSpacing(100), 1);

        vm.expectRevert(); // não dá para habilitar duas vezes
        factory.enableFeeAmount(100, 1);
    }

    function test_createPool_inEveryFeeTier() public {
        factory.enableFeeAmount(100, 1);
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        int24[4] memory spacings = [int24(1), 10, 60, 200];

        for (uint256 i = 0; i < 4; i++) {
            IUniswapV3Pool pool = _newPool(fees[i]);
            assertEq(factory.getPool(address(token0), address(token1), fees[i]), address(pool));
            // a ordem dos tokens na busca não importa
            assertEq(factory.getPool(address(token1), address(token0), fees[i]), address(pool));
            assertEq(pool.fee(), fees[i]);
            assertEq(pool.tickSpacing(), spacings[i]);
            assertEq(pool.token0(), address(token0));
            assertEq(pool.token1(), address(token1));
            assertEq(pool.factory(), address(factory));
            assertEq(_sqrtPrice(pool), PRICE_1);
            assertEq(_tick(pool), 0);
        }
    }

    function test_createPool_revertsOnDuplicateOrInvalid() public {
        _newPool(3000);
        vm.expectRevert(); // mesma pool (par + faixa) duas vezes
        factory.createPool(address(token0), address(token1), 3000);
        vm.expectRevert(); // tokens iguais
        factory.createPool(address(token0), address(token0), 500);
        vm.expectRevert(); // endereço zero
        factory.createPool(address(0), address(token1), 500);
        vm.expectRevert(); // faixa inexistente
        factory.createPool(address(token0), address(token1), 2500);
    }

    function test_initialize_onlyOnce() public {
        IUniswapV3Pool pool = IUniswapV3Pool(factory.createPool(address(token0), address(token1), 3000));
        pool.initialize(PRICE_1);
        vm.expectRevert();
        pool.initialize(PRICE_1);
    }

    // ------------------------------------------------------ posições (liquidez)

    function test_mint_fullRange() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);

        (uint256 a0, uint256 a1) = lp.mint(pool, lower, upper, L);

        // Em preço 1 e faixa completa, os dois tokens entram em proporção ~1:1.
        assertApproxEqRel(a0, L, 1e15);
        assertApproxEqRel(a1, L, 1e15);
        assertEq(pool.liquidity(), L); // preço dentro da faixa: liquidez ativa
        assertEq(token0.balanceOf(address(pool)), a0);
        assertEq(token1.balanceOf(address(pool)), a1);
    }

    function test_mint_narrowRange_isMoreCapitalEfficient() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        (uint256 full0, uint256 full1) = lp.mint(pool, lower, upper, L);

        IUniswapV3Pool pool2 = IUniswapV3Pool(factory.createPool(address(token0), address(token1), 500));
        pool2.initialize(PRICE_1);
        (uint256 n0, uint256 n1) = lp.mint(pool2, -600, 600, L); // ~ ±6%

        // Mesma liquidez L, bem menos capital na faixa estreita (concentração).
        assertLt(n0, full0 / 20);
        assertLt(n1, full1 / 20);
        assertEq(pool2.liquidity(), L);
    }

    function test_mint_outsideCurrentPrice_needsOnlyOneToken() public {
        IUniswapV3Pool pool = _newPool(3000);
        // Faixa acima do preço atual: só token0. Faixa abaixo: só token1.
        (uint256 u0, uint256 u1) = lp.mint(pool, 1200, 1800, L);
        assertGt(u0, 0);
        assertEq(u1, 0);
        (uint256 d0, uint256 d1) = lp.mint(pool, -1800, -1200, L);
        assertEq(d0, 0);
        assertGt(d1, 0);
        assertEq(pool.liquidity(), 0); // nenhuma das duas está ativa
    }

    function test_mint_revertsOnBadTicks() public {
        IUniswapV3Pool pool = _newPool(3000);
        vm.expectRevert();
        lp.mint(pool, -601, 600, L); // não é múltiplo do espaçamento (60)
        vm.expectRevert();
        lp.mint(pool, 600, -600, L); // invertido
        vm.expectRevert();
        lp.mint(pool, -600, 600, 0); // liquidez zero
    }

    // ------------------------------------------------------------------ trocas

    function test_swap_insideRange() public {
        IUniswapV3Pool pool = _newPool(3000);
        lp.mint(pool, -600, 600, L);

        uint256 before1 = token1.balanceOf(address(trader));
        (int256 a0, int256 a1) = trader.swap(pool, true, 1e18, MIN_LIMIT); // token0 -> token1

        assertEq(a0, 1e18); // pagou exatamente o pedido
        assertLt(a1, 0); // recebeu token1
        uint256 out = uint256(-a1);
        assertEq(token1.balanceOf(address(trader)) - before1, out);
        assertLt(out, 1e18 * 997 / 1000); // saiu menos que 1:1 menos a taxa de 0,3%
        assertLt(_sqrtPrice(pool), PRICE_1); // vender token0 derruba o preço
        assertEq(pool.liquidity(), L); // continua dentro da faixa
    }

    function test_swap_exactOutput() public {
        IUniswapV3Pool pool = _newPool(3000);
        lp.mint(pool, -600, 600, L);

        (int256 a0, int256 a1) = trader.swap(pool, true, -1e18, MIN_LIMIT); // quero receber 1e18 de token1
        assertEq(a1, -1e18);
        assertGt(a0, 1e18); // pagou mais que 1:1 (taxa + impacto)
    }

    function test_swap_beyondRange_isPartiallyFilled() public {
        IUniswapV3Pool pool = _newPool(3000);
        (uint256 u0,) = lp.mint(pool, -600, 600, L); // posição estreita (~±6%)
        assertGt(u0, 0);

        // Pedido de 1e20 é maior que a liquidez disponível na faixa (~3e19).
        (int256 a0, int256 a1) = trader.swap(pool, true, 1e20, MIN_LIMIT);

        assertGt(a0, 2.9e19); // consumiu toda a faixa...
        assertLt(a0, 1e20); // ...mas não o pedido inteiro (execução parcial)
        assertLt(a1, 0);
        assertLt(_tick(pool), -600); // preço saiu pela borda inferior
        assertEq(pool.liquidity(), 0); // posição fora da faixa: sem liquidez ativa

        // Fora da faixa (abaixo), a posição virou 100% token0.
        (uint256 b0, uint256 b1) = lp.burn(pool, -600, 600, L);
        assertEq(b1, 0);
        assertGt(b0, 5.9e19);
    }

    function test_swap_priceLimitIsRespected() public {
        IUniswapV3Pool pool = _newPool(3000);
        lp.mint(pool, -600, 600, L);
        uint160 limit = PRICE_1 - PRICE_1 / 1000; // para 0,1% abaixo
        (int256 a0,) = trader.swap(pool, true, 1e20, limit);
        assertLt(a0, 1e20);
        assertEq(_sqrtPrice(pool), limit);

        vm.expectRevert(); // limite do lado errado do preço atual
        trader.swap(pool, true, 1e18, PRICE_1 + 1);
    }

    function test_swap_onlyCallbackPayer_failsIfNotPaid() public {
        IUniswapV3Pool pool = _newPool(3000);
        lp.mint(pool, -600, 600, L);
        PoolActor broke = new PoolActor(); // sem saldo
        vm.expectRevert();
        broke.swap(pool, true, 1e18, MIN_LIMIT);
    }

    // -------------------------------------------- taxas dos provedores: collect

    function test_collect_feesInEveryTier() public {
        factory.enableFeeAmount(100, 1);
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];

        for (uint256 i = 0; i < 4; i++) {
            IUniswapV3Pool pool = _newPool(fees[i]);
            (int24 lower, int24 upper) = _fullRange(fees[i]);
            lp.mint(pool, lower, upper, L);

            trader.swap(pool, true, 1e18, MIN_LIMIT);

            lp.burn(pool, lower, upper, 0); // "cutuca" a posição para registrar as taxas
            uint256 bal0 = token0.balanceOf(address(this));
            (uint128 c0, uint128 c1) = lp.collect(pool, lower, upper, address(this));

            uint256 expectedFee = 1e18 * uint256(fees[i]) / 1e6;
            assertApproxEqAbs(c0, expectedFee, 10); // taxa cobrada em token0 (o que entrou)
            assertEq(c1, 0);
            assertEq(token0.balanceOf(address(this)) - bal0, c0);

            // Uma segunda coleta não traz mais nada.
            (uint128 d0, uint128 d1) = lp.collect(pool, lower, upper, address(this));
            assertEq(d0, 0);
            assertEq(d1, 0);
        }
    }

    function test_collect_outOfRangePositionEarnsNoFees() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        lp.mint(pool, lower, upper, L); // dentro da faixa
        PoolActor lpOut = new PoolActor();
        token0.mint(address(lpOut), 1e30);
        token1.mint(address(lpOut), 1e30);
        lpOut.mint(pool, 1200, 1800, L); // fora da faixa (acima do preço)

        trader.swap(pool, true, 1e18, MIN_LIMIT);

        lp.burn(pool, lower, upper, 0);
        lpOut.burn(pool, 1200, 1800, 0);
        (uint128 in0,) = lp.collect(pool, lower, upper, address(this));
        (uint128 out0, uint128 out1) = lpOut.collect(pool, 1200, 1800, address(this));
        assertGt(in0, 0);
        assertEq(out0, 0);
        assertEq(out1, 0);
    }

    function test_burn_returnsLiquidityAndCollectPaysOut() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        (uint256 m0, uint256 m1) = lp.mint(pool, lower, upper, L);

        (uint256 b0, uint256 b1) = lp.burn(pool, lower, upper, L);
        assertApproxEqAbs(b0, m0, 1); // devolve o que entrou (menos arredondamento)
        assertApproxEqAbs(b1, m1, 1);
        assertEq(pool.liquidity(), 0);

        (uint128 c0, uint128 c1) = lp.collect(pool, lower, upper, address(this));
        assertEq(c0, b0);
        assertEq(c1, b1);
    }

    function test_collect_onlyPositionOwner() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        lp.mint(pool, lower, upper, L);
        trader.swap(pool, true, 1e18, MIN_LIMIT);
        lp.burn(pool, lower, upper, 0);

        // Outro endereço (trader) tenta coletar a mesma faixa: é outra posição, vazia.
        (uint128 c0, uint128 c1) = trader.collect(pool, lower, upper, address(trader));
        assertEq(c0, 0);
        assertEq(c1, 0);
    }

    // ------------------------------------- taxa do protocolo: setFeeProtocol(6,6)

    function test_setFeeProtocol_onlyOwnerAndValidRange() public {
        IUniswapV3Pool pool = _newPool(3000);

        vm.prank(address(0xBAD));
        vm.expectRevert();
        pool.setFeeProtocol(6, 6);

        vm.expectRevert(); // 3 é menor que o mínimo (4)
        pool.setFeeProtocol(3, 6);
        vm.expectRevert(); // 11 é maior que o máximo (10)
        pool.setFeeProtocol(6, 11);

        pool.setFeeProtocol(6, 6);
        (,,,,, uint8 feeProtocol,) = pool.slot0();
        assertEq(feeProtocol, 6 | (6 << 4));

        pool.setFeeProtocol(0, 0); // desligar é permitido
        (,,,,, feeProtocol,) = pool.slot0();
        assertEq(feeProtocol, 0);
    }

    function test_protocolFee_oneSixth_collectedByOwner() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        lp.mint(pool, lower, upper, L);
        pool.setFeeProtocol(6, 6);

        trader.swap(pool, true, 1e18, MIN_LIMIT);

        uint256 totalFee = 1e18 * 3000 / 1e6; // 0,30% = 3e15
        (uint128 p0, uint128 p1) = pool.protocolFees();
        assertApproxEqAbs(p0, totalFee / 6, 10); // 1/6 da taxa (= 0,05% do valor trocado)
        assertEq(p1, 0);

        // Provedor fica com 5/6.
        lp.burn(pool, lower, upper, 0);
        (uint128 lp0,) = lp.collect(pool, lower, upper, address(this));
        assertApproxEqAbs(lp0, totalFee * 5 / 6, 10);

        // Só o owner coleta a parte do protocolo.
        address treasury = address(0xFEE);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        pool.collectProtocol(treasury, type(uint128).max, type(uint128).max);

        (uint128 got0, uint128 got1) = pool.collectProtocol(treasury, type(uint128).max, type(uint128).max);
        assertEq(token0.balanceOf(treasury), got0);
        assertEq(got1, 0);
        assertEq(uint256(got0), uint256(p0) - 1); // o v3 deixa 1 wei na pool (otimização de gás)

        // Também funciona para o token1 (troca no sentido contrário).
        trader.swap(pool, false, 1e18, MAX_LIMIT);
        (, uint128 q1) = pool.protocolFees();
        assertApproxEqAbs(q1, totalFee / 6, 10);
    }

    function test_protocolFee_off_byDefault() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        lp.mint(pool, lower, upper, L);
        trader.swap(pool, true, 1e18, MIN_LIMIT);
        (uint128 p0, uint128 p1) = pool.protocolFees();
        assertEq(p0, 0);
        assertEq(p1, 0);
    }

    function test_ownerCannotTouchLiquidity_andOwnershipTransfers() public {
        IUniswapV3Pool pool = _newPool(3000);
        (int24 lower, int24 upper) = _fullRange(3000);
        (uint256 m0, uint256 m1) = lp.mint(pool, lower, upper, L);

        // O owner (este contrato) não consegue sacar a liquidez do provedor: a posição é de quem depositou.
        vm.expectRevert();
        pool.burn(lower, upper, L);
        assertEq(token0.balanceOf(address(pool)), m0);
        assertEq(token1.balanceOf(address(pool)), m1);

        // Transferência de propriedade: o novo owner manda, o antigo perde o poder.
        address novo = address(0xA11CE);
        factory.setOwner(novo);
        assertEq(factory.owner(), novo);
        vm.expectRevert();
        pool.setFeeProtocol(6, 6);
        vm.prank(novo);
        pool.setFeeProtocol(6, 6);
    }
}
