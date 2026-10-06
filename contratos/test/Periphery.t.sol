// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3Deployer} from "../script/helpers/UniswapV3Deployer.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {INPM, ISwapRouterLike, IQuoterV2Like} from "./helpers/IPeriphery.sol";

interface IWrapped {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/// @notice Etapa 1 do CLAUDE.md, parte "periphery": posições em NFT (adicionar, remover 25/50/75/100%,
///         coletar taxas), SwapRouter, QuoterV2, moeda nativa (POL) e o desenho do NFT.
///         A pilha é montada pelo MESMO código do script de deploy (UniswapV3Deployer).
contract PeripheryTest is Test, UniswapV3Deployer {
    uint160 constant PRICE_1 = 2 ** 96; // preço 1
    uint160 constant PRICE_2 = 112045541949572279837463876454; // preço 2 (token1 por token0), tick ~6931
    int24 constant MAX_TICK = 887272;
    uint128 constant U128_MAX = type(uint128).max;

    Deployed d;
    INPM npm;
    ISwapRouterLike router;
    IQuoterV2Like quoter;
    IUniswapV3Factory factory;
    MockERC20 tA;
    MockERC20 tB;
    MockERC20 tC;
    address wpol;
    address user;
    address trader;

    function setUp() public {
        wpol = _create("WrappedNativeTestnet.sol:WrappedNativeTestnet", abi.encode("Wrapped POL", "WPOL"));
        d = deployAll(wpol, address(0)); // dono da Factory = este contrato de teste
        npm = INPM(d.positionManager);
        router = ISwapRouterLike(d.router);
        quoter = IQuoterV2Like(d.quoter);
        factory = IUniswapV3Factory(d.factory);

        tA = new MockERC20("Token A", "AAA", 18);
        tB = new MockERC20("Token B", "BBB", 18);
        tC = new MockERC20("Token C", "CCC", 18);

        user = makeAddr("user");
        trader = makeAddr("trader");
        MockERC20[3] memory ts = [tA, tB, tC];
        address[2] memory people = [user, trader];
        for (uint256 p = 0; p < 2; p++) {
            vm.deal(people[p], 1000 ether);
            for (uint256 i = 0; i < 3; i++) {
                ts[i].mint(people[p], 1e30);
                vm.startPrank(people[p]);
                ts[i].approve(address(npm), type(uint256).max);
                ts[i].approve(address(router), type(uint256).max);
                vm.stopPrank();
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    function _sorted(address a, address b) internal pure returns (address, address) {
        return a < b ? (a, b) : (b, a);
    }

    function _createPool(address a, address b, uint24 fee, uint160 sqrtP) internal returns (IUniswapV3Pool) {
        (address t0, address t1) = _sorted(a, b);
        return IUniswapV3Pool(npm.createAndInitializePoolIfNecessary(t0, t1, fee, sqrtP));
    }

    function _full(uint24 fee) internal view returns (int24 lo, int24 hi) {
        int24 s = factory.feeAmountTickSpacing(fee);
        hi = (MAX_TICK / s) * s;
        lo = -hi;
    }

    function _params(address a, address b, uint24 fee, int24 lo, int24 hi, uint256 amt, address to)
        internal
        view
        returns (INPM.MintParams memory p)
    {
        (address t0, address t1) = _sorted(a, b);
        p = INPM.MintParams(t0, t1, fee, lo, hi, amt, amt, 0, 0, to, block.timestamp + 1 hours);
    }

    function _mintAs(address who, INPM.MintParams memory p)
        internal
        returns (uint256 id, uint128 liq, uint256 a0, uint256 a1)
    {
        vm.startPrank(who);
        (id, liq, a0, a1) = npm.mint(p);
        vm.stopPrank();
    }

    function _pos(uint256 id) internal view returns (uint128 liq, uint128 owed0, uint128 owed1) {
        (,,,,,,, liq,,, owed0, owed1) = npm.positions(id);
    }

    function _slot(IUniswapV3Pool pool) internal view returns (uint160 p, int24 tick) {
        (p, tick,,,,,) = pool.slot0();
    }

    function _startsWith(bytes memory s, bytes memory prefix) internal pure returns (bool) {
        if (s.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (s[i] != prefix[i]) return false;
        }
        return true;
    }

    // ------------------------------------------------- criar pool (preço inicial)

    function test_createPool_initialPriceAndIdempotent() public {
        (address t0, address t1) = _sorted(address(tA), address(tB));
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 500, PRICE_2);
        (uint160 p,) = _slot(pool);
        assertEq(p, PRICE_2); // preço inicial escolhido pelo criador
        assertEq(factory.getPool(t0, t1, 500), address(pool));

        // Chamar de novo (outro preço) não muda nada nem cria outra pool.
        address again = npm.createAndInitializePoolIfNecessary(t0, t1, 500, PRICE_1);
        assertEq(again, address(pool));
        (p,) = _slot(pool);
        assertEq(p, PRICE_2);
    }

    function test_createPool_requiresSortedTokens() public {
        (address t0, address t1) = _sorted(address(tA), address(tB));
        vm.expectRevert();
        npm.createAndInitializePoolIfNecessary(t1, t0, 3000, PRICE_1);
    }

    function test_createPool_poolAlreadyCreatedButNotInitialized_isInitialized() public {
        (address t0, address t1) = _sorted(address(tA), address(tB));
        factory.createPool(t0, t1, 3000); // alguém criou sem preço
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(t0, t1, 3000));
        npm.createAndInitializePoolIfNecessary(t0, t1, 3000, PRICE_2);
        (uint160 p,) = _slot(pool);
        assertEq(p, PRICE_2);
    }

    // ---------------------------------------------------- criar posição (NFT)

    function test_mint_fullRange_createsNft() public {
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (address t0, address t1) = _sorted(address(tA), address(tB));

        uint256 bal0 = MockERC20(t0).balanceOf(user);
        (uint256 id, uint128 liq, uint256 a0, uint256 a1) =
            _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        assertEq(id, 1);
        assertEq(npm.ownerOf(id), user);
        assertEq(npm.balanceOf(user), 1);
        assertGt(liq, 0);
        assertApproxEqRel(a0, 1e21, 1e15); // preço 1, faixa completa: ~1:1
        assertApproxEqRel(a1, 1e21, 1e15);
        assertEq(bal0 - MockERC20(t0).balanceOf(user), a0);
        assertEq(pool.liquidity(), liq);

        _checkPosition(id, t0, t1, 3000, lo, hi, liq);
    }

    function _checkPosition(uint256 id, address t0, address t1, uint24 fee, int24 lo, int24 hi, uint128 liq)
        internal
        view
    {
        (,, address p0, address p1, uint24 pfee, int24 plo, int24 phi, uint128 pliq,,,,) = npm.positions(id);
        assertEq(p0, t0);
        assertEq(p1, t1);
        assertEq(pfee, fee);
        assertEq(plo, lo);
        assertEq(phi, hi);
        assertEq(pliq, liq);
    }

    function test_mint_customRange_atPriceTwo() public {
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 3000, PRICE_2);
        (, int24 tick) = _slot(pool);
        assertEq(tick, 6931);

        // Faixa personalizada em volta do preço (~ -5% a +4%), múltiplos de 60
        (uint256 id, uint128 liq, uint256 a0, uint256 a1) =
            _mintAs(user, _params(address(tA), address(tB), 3000, 6600, 7200, 1e21, user));
        assertGt(a0, 0);
        assertGt(a1, 0); // dentro da faixa: os dois tokens entram
        assertGt(a1, a0); // preço 2: o token1 pesa ~2x por unidade de token0
        assertEq(pool.liquidity(), liq);
        (uint128 pl,,) = _pos(id);
        assertEq(pl, liq);
    }

    function test_mint_singleSided_whenRangeIsOutsidePrice() public {
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 3000, PRICE_2); // tick 6931

        // Faixa acima do preço: só token0.
        (, uint128 liqUp, uint256 u0, uint256 u1) =
            _mintAs(user, _params(address(tA), address(tB), 3000, 7800, 8400, 1e21, user));
        assertGt(u0, 0);
        assertEq(u1, 0);
        assertGt(liqUp, 0);
        assertEq(pool.liquidity(), 0); // "Fora da faixa": sem liquidez ativa

        // Faixa abaixo do preço: só token1.
        (,, uint256 d0, uint256 d1) = _mintAs(user, _params(address(tA), address(tB), 3000, 4800, 5400, 1e21, user));
        assertEq(d0, 0);
        assertGt(d1, 0);
        assertEq(pool.liquidity(), 0);
    }

    function test_mint_inEveryFeeTier() public {
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        for (uint256 i = 0; i < 4; i++) {
            _createPool(address(tA), address(tB), fees[i], PRICE_1);
            (int24 lo, int24 hi) = _full(fees[i]);
            (uint256 id, uint128 liq,,) = _mintAs(user, _params(address(tA), address(tB), fees[i], lo, hi, 1e21, user));
            assertEq(id, i + 1); // um NFT por posição
            assertGt(liq, 0);
        }
        assertEq(npm.balanceOf(user), 4);
    }

    function test_mint_protectsAgainstSlippageAndExpiredDeadline() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);

        INPM.MintParams memory p = _params(address(tA), address(tB), 3000, lo, hi, 1e21, user);
        p.amount0Min = 1e21 + 1; // exige mais do que o desejado: impossível
        vm.prank(user);
        vm.expectRevert(bytes("Price slippage check"));
        npm.mint(p);

        p = _params(address(tA), address(tB), 3000, lo, hi, 1e21, user);
        vm.warp(10_000);
        p.deadline = block.timestamp - 1;
        vm.prank(user);
        vm.expectRevert(bytes("Transaction too old"));
        npm.mint(p);
    }

    // ------------------------------------- adicionar / remover liquidez, burn

    function test_increaseLiquidity_addsToSamePosition() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (uint256 id, uint128 liq,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        vm.prank(user);
        (uint128 added,,) = npm.increaseLiquidity(INPM.IncreaseLiquidityParams(id, 1e21, 1e21, 0, 0, block.timestamp + 1));
        (uint128 total,,) = _pos(id);
        assertEq(total, liq + added);
        assertApproxEqRel(added, liq, 1e12);
        assertEq(npm.balanceOf(user), 1); // continua sendo 1 NFT
    }

    function test_decreaseLiquidity_25_50_75_100_percent() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        uint256[4] memory pcts = [uint256(25), 50, 75, 100];

        for (uint256 i = 0; i < 4; i++) {
            (uint256 id, uint128 liq, uint256 m0, uint256 m1) =
                _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));
            uint128 part = uint128(uint256(liq) * pcts[i] / 100);

            vm.startPrank(user);
            (uint256 r0, uint256 r1) = npm.decreaseLiquidity(INPM.DecreaseLiquidityParams(id, part, 0, 0, block.timestamp + 1));
            vm.stopPrank();

            assertApproxEqRel(r0, m0 * pcts[i] / 100, 1e12);
            assertApproxEqRel(r1, m1 * pcts[i] / 100, 1e12);
            (uint128 left, uint128 owed0, uint128 owed1) = _pos(id);
            assertEq(left, liq - part);
            assertEq(owed0, r0); // o que saiu da liquidez fica "a coletar" no NFT
            assertEq(owed1, r1);

            // Coletar manda os tokens para a carteira.
            uint256 before0 = MockERC20(npm_t0()).balanceOf(user);
            vm.prank(user);
            (uint256 c0,) = npm.collect(INPM.CollectParams(id, user, U128_MAX, U128_MAX));
            assertEq(c0, r0);
            assertEq(MockERC20(npm_t0()).balanceOf(user) - before0, c0);
        }
    }

    function npm_t0() internal view returns (address t0) {
        (t0,) = _sorted(address(tA), address(tB));
    }

    function test_burn_onlyWhenFullyRemovedAndCollected() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (uint256 id, uint128 liq,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        vm.prank(user);
        vm.expectRevert(bytes("Not cleared")); // ainda tem liquidez
        npm.burn(id);

        vm.startPrank(user);
        npm.decreaseLiquidity(INPM.DecreaseLiquidityParams(id, liq, 0, 0, block.timestamp + 1));
        vm.expectRevert(bytes("Not cleared")); // falta coletar
        npm.burn(id);

        npm.collect(INPM.CollectParams(id, user, U128_MAX, U128_MAX));
        npm.burn(id); // agora pode
        vm.stopPrank();

        vm.expectRevert(); // NFT não existe mais
        npm.ownerOf(id);
    }

    // ------------------------------------- taxas dos provedores via NFT (collect)

    function test_collectFees_throughNft_afterRouterSwap() public {
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (address t0, address t1) = _sorted(address(tA), address(tB));
        (uint256 id,,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        vm.prank(trader);
        router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams(t0, t1, 3000, trader, block.timestamp + 1, 1e18, 0, 0)
        );

        vm.prank(user);
        (uint256 f0, uint256 f1) = npm.collect(INPM.CollectParams(id, user, U128_MAX, U128_MAX));
        assertApproxEqAbs(f0, 3e15, 20); // 0,30% de 1e18, tudo para o provedor (taxa do protocolo desligada)
        assertEq(f1, 0);
        assertEq(pool.liquidity() > 0, true);
    }

    function test_collectFees_withProtocolFee_oneSixthToExchange() public {
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (address t0, address t1) = _sorted(address(tA), address(tB));
        (uint256 id,,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));
        pool.setFeeProtocol(6, 6); // este contrato é o dono da Factory

        vm.prank(trader);
        router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams(t0, t1, 3000, trader, block.timestamp + 1, 1e18, 0, 0)
        );

        vm.prank(user);
        (uint256 f0,) = npm.collect(INPM.CollectParams(id, user, U128_MAX, U128_MAX));
        assertApproxEqAbs(f0, 3e15 * 5 / 6, 20); // provedor: 5/6 (0,25% do valor)

        (uint128 p0,) = pool.protocolFees();
        assertApproxEqAbs(p0, 3e15 / 6, 20); // exchange: 1/6 (0,05% do valor)

        address treasury = makeAddr("treasury");
        (uint128 got0,) = pool.collectProtocol(treasury, U128_MAX, U128_MAX);
        assertEq(MockERC20(t0).balanceOf(treasury), got0);
        assertEq(uint256(got0), uint256(p0) - 1);
    }

    // -------------------------------------------------------- permissões do NFT

    function test_nft_onlyOwnerOrApprovedCanManage() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (uint256 id, uint128 liq,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        vm.startPrank(trader); // outra pessoa
        vm.expectRevert(bytes("Not approved"));
        npm.decreaseLiquidity(INPM.DecreaseLiquidityParams(id, liq, 0, 0, block.timestamp + 1));
        vm.expectRevert(bytes("Not approved"));
        npm.collect(INPM.CollectParams(id, trader, U128_MAX, U128_MAX));
        vm.expectRevert(bytes("Not approved"));
        npm.burn(id);
        vm.stopPrank();

        // Com aprovação do dono, passa a poder.
        vm.prank(user);
        npm.approve(trader, id);
        vm.prank(trader);
        npm.decreaseLiquidity(INPM.DecreaseLiquidityParams(id, liq / 2, 0, 0, block.timestamp + 1));
    }

    function test_nft_transferMovesControl() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (uint256 id, uint128 liq,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        vm.prank(user);
        npm.transferFrom(user, trader, id);
        assertEq(npm.ownerOf(id), trader);

        vm.prank(user);
        vm.expectRevert(bytes("Not approved"));
        npm.decreaseLiquidity(INPM.DecreaseLiquidityParams(id, liq, 0, 0, block.timestamp + 1));

        vm.prank(trader);
        npm.decreaseLiquidity(INPM.DecreaseLiquidityParams(id, liq, 0, 0, block.timestamp + 1));
    }

    // ------------------------------------------------------- SwapRouter + Quoter

    function _poolWithLiquidity(address a, address b, uint24 fee) internal {
        _createPool(a, b, fee, PRICE_1);
        (int24 lo, int24 hi) = _full(fee);
        _mintAs(user, _params(a, b, fee, lo, hi, 1e24, user));
    }

    function test_router_exactInputSingle_matchesQuoter_andProtectsSlippage() public {
        _poolWithLiquidity(address(tA), address(tB), 3000);

        (uint256 quoted,,,) =
            quoter.quoteExactInputSingle(IQuoterV2Like.QuoteExactInputSingleParams(address(tA), address(tB), 1e18, 3000, 0));
        assertGt(quoted, 0);
        assertLt(quoted, 1e18 * 997 / 1000);

        // Mínimo recebido acima do possível: falha e nada é cobrado.
        vm.startPrank(trader);
        vm.expectRevert(bytes("Too little received"));
        router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams(
                address(tA), address(tB), 3000, trader, block.timestamp + 1, 1e18, quoted + 1, 0
            )
        );

        uint256 inBefore = tA.balanceOf(trader);
        uint256 outBefore = tB.balanceOf(trader);
        uint256 out = router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams(
                address(tA), address(tB), 3000, trader, block.timestamp + 1, 1e18, quoted, 0
            )
        );
        vm.stopPrank();

        assertEq(out, quoted); // a cotação do QuoterV2 é exatamente o que foi recebido
        assertEq(inBefore - tA.balanceOf(trader), 1e18);
        assertEq(tB.balanceOf(trader) - outBefore, out);
    }

    function test_router_deadline() public {
        _poolWithLiquidity(address(tA), address(tB), 3000);
        vm.warp(10_000);
        vm.prank(trader);
        vm.expectRevert(bytes("Transaction too old"));
        router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams(address(tA), address(tB), 3000, trader, block.timestamp - 1, 1e18, 0, 0)
        );
    }

    function test_router_exactOutputSingle() public {
        _poolWithLiquidity(address(tA), address(tB), 3000);

        (uint256 quotedIn,,,) = quoter.quoteExactOutputSingle(
            IQuoterV2Like.QuoteExactOutputSingleParams(address(tA), address(tB), 1e18, 3000, 0)
        );
        assertGt(quotedIn, 1e18); // paga mais que 1:1 (taxa + impacto)

        vm.startPrank(trader);
        vm.expectRevert(bytes("Too much requested"));
        router.exactOutputSingle(
            ISwapRouterLike.ExactOutputSingleParams(
                address(tA), address(tB), 3000, trader, block.timestamp + 1, 1e18, quotedIn - 1, 0
            )
        );

        uint256 outBefore = tB.balanceOf(trader);
        uint256 paid = router.exactOutputSingle(
            ISwapRouterLike.ExactOutputSingleParams(
                address(tA), address(tB), 3000, trader, block.timestamp + 1, 1e18, quotedIn, 0
            )
        );
        vm.stopPrank();

        assertEq(paid, quotedIn);
        assertEq(tB.balanceOf(trader) - outBefore, 1e18); // recebeu exatamente o pedido
    }

    function test_router_multihop_A_to_B_to_C() public {
        _poolWithLiquidity(address(tA), address(tB), 3000);
        _poolWithLiquidity(address(tB), address(tC), 500);
        bytes memory path = abi.encodePacked(address(tA), uint24(3000), address(tB), uint24(500), address(tC));

        (uint256 quoted,,,) = quoter.quoteExactInput(path, 1e18);
        assertGt(quoted, 0);
        assertLt(quoted, 1e18 * 997 / 1000 * 9995 / 10000); // duas taxas (0,30% + 0,05%) descontadas

        uint256 cBefore = tC.balanceOf(trader);
        uint256 aBefore = tA.balanceOf(trader);
        vm.prank(trader);
        uint256 out = router.exactInput(ISwapRouterLike.ExactInputParams(path, trader, block.timestamp + 1, 1e18, quoted));

        assertEq(out, quoted);
        assertEq(tC.balanceOf(trader) - cBefore, out);
        assertEq(aBefore - tA.balanceOf(trader), 1e18);
        assertEq(tB.balanceOf(trader), 1e30); // o token do meio não fica com ninguém (só passa)
    }

    function test_router_swapThatCrossesOutOfRange_isPartialOnExactInput() public {
        // Só liquidez estreita (~±6%) e limite de preço de 1%: o pedido grande é atendido só até o limite.
        IUniswapV3Pool pool = _createPool(address(tA), address(tB), 3000, PRICE_1);
        _mintAs(user, _params(address(tA), address(tB), 3000, -600, 600, 1e21, user));
        (address t0, address t1) = _sorted(address(tA), address(tB));

        uint256 t0Before = MockERC20(t0).balanceOf(trader);
        vm.prank(trader);
        // com limite de preço, só a parte executada é cobrada
        uint256 out = router.exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams(
                t0, t1, 3000, trader, block.timestamp + 1, 1e22, 0, uint160(PRICE_1 - PRICE_1 / 100)
            )
        );
        assertGt(out, 0);
        (uint160 p,) = _slot(pool);
        assertEq(p, uint160(PRICE_1 - PRICE_1 / 100)); // parou no limite de preço
        uint256 spent = t0Before - MockERC20(t0).balanceOf(trader);
        assertGt(spent, 0);
        assertLt(spent, 1e22); // só uma parte do pedido foi cobrada (o resto não foi executado)
    }

    // --------------------------------------------------- moeda nativa (POL)

    function test_native_addLiquidityWithPol_andRefund() public {
        _createPool(wpol, address(tA), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        INPM.MintParams memory p = _params(wpol, address(tA), 3000, lo, hi, 100 ether, user);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(INPM.mint, (p));
        calls[1] = abi.encodeCall(INPM.refundETH, ());

        uint256 ethBefore = user.balance;
        vm.prank(user);
        npm.multicall{value: 150 ether}(calls); // manda 150 POL, usa ~100, o resto volta

        uint256 spent = ethBefore - user.balance;
        assertApproxEqRel(spent, 100 ether, 1e15);
        assertEq(address(npm).balance, 0); // nada fica preso no contrato
        assertEq(npm.ownerOf(1), user);
    }

    function test_native_swap_inAndOut() public {
        // liquidez com POL
        _createPool(wpol, address(tA), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        bytes[] memory mintCalls = new bytes[](2);
        mintCalls[0] = abi.encodeCall(INPM.mint, (_params(wpol, address(tA), 3000, lo, hi, 500 ether, user)));
        mintCalls[1] = abi.encodeCall(INPM.refundETH, ());
        vm.prank(user);
        npm.multicall{value: 600 ether}(mintCalls);

        // POL -> token: o trader manda POL junto com a chamada
        uint256 ethBefore = trader.balance;
        uint256 aBefore = tA.balanceOf(trader);
        vm.prank(trader);
        uint256 out = router.exactInputSingle{value: 1 ether}(
            ISwapRouterLike.ExactInputSingleParams(wpol, address(tA), 3000, trader, block.timestamp + 1, 1 ether, 0, 0)
        );
        assertEq(ethBefore - trader.balance, 1 ether);
        assertEq(tA.balanceOf(trader) - aBefore, out);

        // token -> POL: o roteador recebe WPOL e converte em POL para o trader (unwrapWETH9)
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            ISwapRouterLike.exactInputSingle,
            (ISwapRouterLike.ExactInputSingleParams(address(tA), wpol, 3000, address(0), block.timestamp + 1, out, 0, 0))
        );
        calls[1] = abi.encodeCall(ISwapRouterLike.unwrapWETH9, (0, trader));
        ethBefore = trader.balance;
        vm.prank(trader);
        router.multicall(calls);
        uint256 gotPol = trader.balance - ethBefore;
        assertGt(gotPol, 0);
        assertLt(gotPol, 1 ether); // ida e volta custa 2 taxas de 0,30% + impacto
        assertEq(IWrapped(wpol).balanceOf(address(router)), 0); // nada de WPOL preso no roteador
    }

    // --------------------------------------------------------- desenho do NFT

    function test_nft_tokenURI_worksAndLibraryIsLinked() public {
        _createPool(address(tA), address(tB), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        (uint256 id,,,) = _mintAs(user, _params(address(tA), address(tB), 3000, lo, hi, 1e21, user));

        string memory uri = npm.tokenURI(id);
        assertTrue(_startsWith(bytes(uri), "data:application/json;base64,"), "formato do tokenURI");
        assertGt(bytes(uri).length, 1000); // contém o SVG da posição (gerado pela biblioteca ligada)

        vm.expectRevert(); // NFT que não existe
        npm.tokenURI(999);
    }

    function test_nft_tokenURI_showsPol_notEth() public {
        _createPool(wpol, address(tA), 3000, PRICE_1);
        (int24 lo, int24 hi) = _full(3000);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(INPM.mint, (_params(wpol, address(tA), 3000, lo, hi, 10 ether, user)));
        calls[1] = abi.encodeCall(INPM.refundETH, ());
        vm.prank(user);
        npm.multicall{value: 20 ether}(calls);

        bytes memory uri = bytes(npm.tokenURI(1));
        bytes memory json = _b64decode(_after(uri, "data:application/json;base64,"));
        bytes memory svg = _b64decode(_after(json, "data:image/svg+xml;base64,"));

        // O token embrulhado aparece como POL (e não ETH), tanto no JSON quanto no desenho (SVG).
        assertTrue(_contains(json, "POL"), "JSON sem POL");
        assertTrue(_contains(svg, "POL"), "SVG sem POL");
        assertFalse(_contains(json, "ETH"), "JSON ainda tem ETH");
        assertFalse(_contains(svg, "ETH"), "SVG ainda tem ETH");
        assertTrue(_contains(json, "AAA"), "JSON sem o outro token");
    }

    function test_nft_nameAndSymbol_areKambiodex() public view {
        assertEq(npm.name(), "KAMBIODEX V3 Positions");
        assertEq(npm.symbol(), "KBX-V3-POS");
    }

    // ---- utilitários de texto (só para os testes do NFT)

    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        if (needle.length > hay.length) return false;
        for (uint256 i = 0; i + needle.length <= hay.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (hay[i + j] != needle[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    /// Texto que vem depois de `marker`, até a próxima aspa (") ou o fim.
    function _after(bytes memory text, bytes memory marker) internal pure returns (bytes memory out) {
        require(text.length >= marker.length, "texto curto");
        for (uint256 i = 0; i + marker.length <= text.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < marker.length; j++) {
                if (text[i + j] != marker[j]) {
                    ok = false;
                    break;
                }
            }
            if (!ok) continue;
            uint256 start = i + marker.length;
            uint256 end = start;
            while (end < text.length && text[end] != '"') end++;
            out = new bytes(end - start);
            for (uint256 k = 0; k < out.length; k++) out[k] = text[start + k];
            return out;
        }
        revert("marcador nao encontrado");
    }

    function _b64decode(bytes memory data) internal pure returns (bytes memory out) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint8[256] memory rev;
        for (uint256 i = 0; i < 64; i++) rev[uint8(table[i])] = uint8(i);
        uint256 len = data.length;
        uint256 pad = len > 0 && data[len - 1] == "=" ? (len > 1 && data[len - 2] == "=" ? 2 : 1) : 0;
        out = new bytes((len / 4) * 3 - pad);
        uint256 o;
        for (uint256 i = 0; i < len; i += 4) {
            uint256 n = (uint256(rev[uint8(data[i])]) << 18) | (uint256(rev[uint8(data[i + 1])]) << 12)
                | (uint256(rev[uint8(data[i + 2])]) << 6) | uint256(rev[uint8(data[i + 3])]);
            if (o < out.length) out[o++] = bytes1(uint8(n >> 16));
            if (o < out.length) out[o++] = bytes1(uint8(n >> 8));
            if (o < out.length) out[o++] = bytes1(uint8(n));
        }
    }
}
