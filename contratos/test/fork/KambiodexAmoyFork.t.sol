// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IKambiodexFactory} from "@kambiodex/core/interfaces/IKambiodexFactory.sol";
import {IKambiodexPool} from "@kambiodex/core/interfaces/IKambiodexPool.sol";
import {MockERC20} from "../helpers/MockERC20.sol";
import {TextUtils} from "../helpers/TextUtils.sol";
import {INPM, ISwapRouterLike, IQuoterV2Like} from "../helpers/IPeriphery.sol";

interface IDescriptorFork {
    function WETH9() external view returns (address);
    function nativeLabel() external view returns (bytes32);
}

/// @notice Simulação 100% local sobre os contratos JÁ PUBLICADOS na Polygon Amoy (chainId 80002).
///
///         ESTE TESTE DEPENDE DO DEPLOY NOVO (código renomeado, KambiodexPool etc.): os endereços NÃO ficam
///         escritos aqui; são lidos de deployments/amoy-kambiodex-v1.json, que só existe depois que o dono
///         roda Deploy.s.sol com --broadcast. Enquanto o arquivo não existir, todos os testes são PULADOS
///         (de propósito: rodar contra o deploy antigo, de antes da renomeação, não prova nada sobre este código).
///         Os arquivos antigos (amoy.json, amoy-descriptor*.json) ficam como histórico e não são usados aqui.
///
///         Usa um "fork": o Foundry copia o estado da rede para a memória e roda tudo ali.
///         Nada é enviado à rede real: sem chave, sem keystore, sem --broadcast e sem gás.
///         O "dono" da Factory é imitado com vm.prank, que só funciona dentro do fork.
contract KambiodexAmoyForkTest is Test, TextUtils {
    string constant RPC = "https://polygon-amoy-bor-rpc.publicnode.com";

    /// Arquivo gravado pelo Deploy.s.sol (--broadcast). DEPENDE DO DEPLOY NOVO.
    string constant DEPLOY_FILE = "/../deployments/amoy-kambiodex-v1.json";

    // Endereços do deploy novo, lidos do arquivo acima em setUp().
    address factoryAddr;
    address npmAddr;
    address routerAddr;
    address quoterAddr;
    address descriptorAddr;
    /// Dono da Factory depois do deploy = OWNER_ADDRESS usado no deploy (a MetaMask do dono do projeto).
    address ownerAddr;
    bytes32 jsonPoolInitCodeHash;

    uint24 constant FEE = 3000;
    uint160 constant PRICE_1 = 2 ** 96; // preço 1:1
    int24 constant FULL_TICK = 887220; // maior múltiplo de 60 dentro do limite (faixa completa)
    uint128 constant U128_MAX = type(uint128).max;

    IKambiodexFactory factory;
    INPM npm;
    ISwapRouterLike router;
    IQuoterV2Like quoter;

    MockERC20 t0;
    MockERC20 t1;
    IKambiodexPool pool;
    address lp = makeAddr("lp");
    address trader = makeAddr("trader");
    address treasury = makeAddr("treasury");
    uint256 tokenId;

    function setUp() public {
        // DEPENDE DO DEPLOY NOVO: sem o arquivo de endereços, pula tudo.
        string memory path = string.concat(vm.projectRoot(), DEPLOY_FILE);
        if (!vm.exists(path)) {
            vm.skip(true, "deploy novo da Amoy ainda nao feito: falta deployments/amoy-kambiodex-v1.json");
        }
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonUint(json, ".chainId"), 80002, "arquivo nao e da Amoy");
        factoryAddr = vm.parseJsonAddress(json, ".KambiodexFactory");
        npmAddr = vm.parseJsonAddress(json, ".NonfungiblePositionManager");
        routerAddr = vm.parseJsonAddress(json, ".SwapRouter");
        quoterAddr = vm.parseJsonAddress(json, ".QuoterV2");
        descriptorAddr = vm.parseJsonAddress(json, ".KambiodexPositionDescriptor");
        ownerAddr = vm.parseJsonAddress(json, ".owner");
        jsonPoolInitCodeHash = vm.parseJsonBytes32(json, ".poolInitCodeHash");
        factory = IKambiodexFactory(factoryAddr);
        npm = INPM(npmAddr);
        router = ISwapRouterLike(routerAddr);
        quoter = IQuoterV2Like(quoterAddr);

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
            t0.approve(npmAddr, type(uint256).max);
            t1.approve(npmAddr, type(uint256).max);
            t0.approve(routerAddr, type(uint256).max);
            t1.approve(routerAddr, type(uint256).max);
            vm.stopPrank();
        }

        // cria + inicializa a pool (fee 3000, preço 1:1) e adiciona liquidez em faixa completa
        pool = IKambiodexPool(npm.createAndInitializePoolIfNecessary(address(t0), address(t1), FEE, PRICE_1));
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
        assertEq(factory.owner(), ownerAddr, "dono da Factory");
        assertEq(factory.feeAmountTickSpacing(100), 1, "faixa 0,01% habilitada");
        assertEq(factory.feeAmountTickSpacing(500), 10, "faixa 0,05%");
        assertEq(factory.feeAmountTickSpacing(3000), 60, "faixa 0,30%");
        assertEq(factory.feeAmountTickSpacing(10000), 200, "faixa 1%");
        assertEq(npm.factory(), factoryAddr, "NPM aponta para a Factory publicada");
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
        vm.prank(ownerAddr);
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
        vm.prank(ownerAddr);
        (uint128 got0, uint128 got1) = pool.collectProtocol(treasury, U128_MAX, U128_MAX);
        assertEq(got0, p0 - 1);
        assertEq(got1, p1 - 1);
        assertEq(t0.balanceOf(treasury), got0);
        assertEq(t1.balanceOf(treasury), got1);
        (uint128 r0, uint128 r1) = pool.protocolFees();
        assertEq(r0, 1);
        assertEq(r1, 1);
    }

    // (7) hash da pool e descriptor do deploy novo
    function test_7_pool_hash_and_descriptor() public view {
        // o hash gravado no JSON é o do bytecode da KambiodexPool compilada neste projeto
        assertEq(jsonPoolInitCodeHash, keccak256(vm.getCode("KambiodexPool.sol:KambiodexPool")), "hash do JSON");
        // (a prova on-chain é o test_2: o NPM calcula o endereço da pool com o hash e a Factory cria no mesmo endereço)
        IDescriptorFork ds = IDescriptorFork(descriptorAddr);
        assertEq(ds.nativeLabel(), bytes32("POL"), "rotulo da moeda nativa");
        assertTrue(ds.WETH9() != address(0), "WETH9 do descriptor");
        bytes memory uri = bytes(npm.tokenURI(tokenId));
        assertTrue(_startsWith(uri, "data:application/json;base64,"), "formato do tokenURI");
        assertFalse(_contains(_lower(uri), "uniswap"), "tokenURI nao pode citar a marca");
    }

    // (6) nome/símbolo do NFT da posição
    function test_6_nft_name() public view {
        assertEq(npm.name(), "KAMBIODEX V3 Positions");
        assertEq(npm.symbol(), "KBX-V3-POS");
    }
}
