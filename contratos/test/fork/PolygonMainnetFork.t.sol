// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3Deployer} from "../../script/helpers/UniswapV3Deployer.sol";
import {DeployPolygon} from "../../script/DeployPolygon.s.sol";
import {MockERC20} from "../helpers/MockERC20.sol";
import {TextUtils} from "../helpers/TextUtils.sol";
import {INPM, ISwapRouterLike, IQuoterV2Like} from "../helpers/IPeriphery.sol";

interface IERC20Info {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
}

/// @notice Simulação 100% local sobre um FORK da Polygon PoS (rede principal, chainId 137).
///         O Foundry copia o estado da rede para a memória; nada é enviado à rede real
///         (sem chave, sem keystore, sem --broadcast, sem gás). Usa o WPOL REAL da Polygon.
contract PolygonMainnetForkTest is Test, UniswapV3Deployer, TextUtils {
    string constant RPC = "https://polygon-bor-rpc.publicnode.com";

    address constant WPOL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant OWNER = 0x000000000000000000000000000000000000dEaD; // dono fictício, só no fork

    uint160 constant PRICE_1 = 2 ** 96;
    int24 constant MAX_TICK = 887272;

    Deployed d;
    INPM npm;
    ISwapRouterLike router;
    IQuoterV2Like quoter;
    IUniswapV3Factory factory;
    MockERC20 usdc; // token de teste (6 casas, como o USDC), criado só dentro do fork
    address lp = makeAddr("lp");
    address trader = makeAddr("trader");

    function setUp() public {
        vm.createSelectFork(RPC);
        assertEq(block.chainid, 137, "nao e a Polygon");

        d = deployAll(WPOL, OWNER);
        npm = INPM(d.positionManager);
        router = ISwapRouterLike(d.router);
        quoter = IQuoterV2Like(d.quoter);
        factory = IUniswapV3Factory(d.factory);

        usdc = new MockERC20("USD Coin (teste)", "USDC", 6);
        address[2] memory people = [lp, trader];
        for (uint256 i = 0; i < 2; i++) {
            usdc.mint(people[i], 1e18);
            vm.deal(people[i], 1_000_000 ether);
            vm.startPrank(people[i]);
            usdc.approve(d.positionManager, type(uint256).max);
            usdc.approve(d.router, type(uint256).max);
            vm.stopPrank();
        }
    }

    /// Pool WPOL/USDC(teste) a 0,30%, liquidez em faixa completa posta em POL nativo. Retorna o id do NFT.
    function _poolWithNativeLiquidity() internal returns (uint256 id) {
        (address t0, address t1) = WPOL < address(usdc) ? (WPOL, address(usdc)) : (address(usdc), WPOL);
        npm.createAndInitializePoolIfNecessary(t0, t1, 3000, PRICE_1);
        int24 hi = (MAX_TICK / 60) * 60;
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            INPM.mint,
            (INPM.MintParams(t0, t1, 3000, -hi, hi, 1_000e6, 1_000e6, 0, 0, lp, block.timestamp + 1 hours))
        );
        calls[1] = abi.encodeCall(INPM.refundETH, ());
        vm.prank(lp);
        npm.multicall{value: 10_000 ether}(calls);
        id = 1;
    }

    // ---------------------------------------------------------------- WPOL real

    function test_realWpol_isWpol() public view {
        assertGt(WPOL.code.length, 0, "WPOL sem codigo");
        assertEq(IERC20Info(WPOL).symbol(), "WPOL");
        assertEq(IERC20Info(WPOL).decimals(), 18);
    }

    // ---------------------------------------------------------------- pilha publicada no fork

    function test_stack_state() public view {
        assertEq(factory.owner(), OWNER, "dono da Factory");
        assertEq(factory.feeAmountTickSpacing(100), 1);
        assertEq(factory.feeAmountTickSpacing(500), 10);
        assertEq(factory.feeAmountTickSpacing(3000), 60);
        assertEq(factory.feeAmountTickSpacing(10000), 200);
        assertEq(npm.WETH9(), WPOL);
        assertEq(npm.name(), "KAMBIODEX V3 Positions");
    }

    function test_protocolFee_onlyOwner_setFeeProtocol() public {
        _poolWithNativeLiquidity();
        (address t0, address t1) = WPOL < address(usdc) ? (WPOL, address(usdc)) : (address(usdc), WPOL);
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(t0, t1, 3000));
        vm.expectRevert();
        pool.setFeeProtocol(6, 6);
        vm.prank(OWNER);
        pool.setFeeProtocol(6, 6);
        (,,,,, uint8 fp,) = pool.slot0();
        assertEq(fp, (6 << 4) | 6);
    }

    // ---------------------------------------------------------------- POL nativo (entrada e saída)

    function test_nativePol_in_thenOutViaUnwrapWETH9() public {
        _poolWithNativeLiquidity();
        assertEq(address(npm).balance, 0, "POL preso no NPM");

        // entrada: POL nativo -> token (o trader manda POL junto com a chamada)
        uint256 polBefore = trader.balance;
        vm.prank(trader);
        uint256 got = router.exactInputSingle{value: 1 ether}(
            ISwapRouterLike.ExactInputSingleParams(WPOL, address(usdc), 3000, trader, block.timestamp + 1, 1 ether, 0, 0)
        );
        assertEq(polBefore - trader.balance, 1 ether, "POL gasto");
        assertEq(usdc.balanceOf(trader), 1e18 + got, "token recebido");

        // saída em POL NATIVO: troca com destino = roteador e depois unwrapWETH9 para o trader
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            ISwapRouterLike.exactInputSingle,
            (ISwapRouterLike.ExactInputSingleParams(address(usdc), WPOL, 3000, address(0), block.timestamp + 1, got, 0, 0))
        );
        calls[1] = abi.encodeCall(ISwapRouterLike.unwrapWETH9, (0, trader));
        polBefore = trader.balance;
        uint256 wpolBefore = IERC20Info(WPOL).balanceOf(trader);
        vm.prank(trader);
        router.multicall(calls);

        uint256 polOut = trader.balance - polBefore;
        assertGt(polOut, 0, "nenhum POL nativo recebido");
        assertLt(polOut, 1 ether, "ida e volta custa taxas");
        assertEq(IERC20Info(WPOL).balanceOf(trader), wpolBefore, "saiu como WPOL, nao como POL nativo");
        assertEq(IERC20Info(WPOL).balanceOf(d.router), 0, "WPOL preso no roteador");
        assertEq(d.router.balance, 0, "POL preso no roteador");
    }

    function test_nativePol_unwrapRespectsMinimum() public {
        _poolWithNativeLiquidity();
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            ISwapRouterLike.exactInputSingle,
            (ISwapRouterLike.ExactInputSingleParams(address(usdc), WPOL, 3000, address(0), block.timestamp + 1, 1e6, 0, 0))
        );
        calls[1] = abi.encodeCall(ISwapRouterLike.unwrapWETH9, (type(uint256).max, trader)); // mínimo impossível
        vm.prank(trader);
        vm.expectRevert();
        router.multicall(calls);
    }

    // ---------------------------------------------------------------- NFT com o WPOL real

    function test_nft_showsPol_withRealWpol() public {
        uint256 id = _poolWithNativeLiquidity();
        bytes memory uri = bytes(npm.tokenURI(id));
        bytes memory json = _b64decode(_tail(uri, "data:application/json;base64,"));
        string memory name = vm.parseJsonString(string(json), ".name");
        assertEq(name, "KAMBIODEX V3 Position - 0,3% - USDC/POL - MIN<>MAX");
        assertFalse(_contains(_lower(json), "uniswap"));
        assertFalse(_contains(json, "WPOL"));
    }

    // ---------------------------------------------------------------- script de deploy da mainnet

    /// (Um teste só, em sequência: variáveis de ambiente são compartilhadas entre testes paralelos.)
    function test_deployScript_inFork_refusalsAndDryRun() public {
        DeployPolygon script = new DeployPolygon();
        string memory path = string.concat(vm.projectRoot(), "/../deployments/polygon.json");
        assertFalse(vm.exists(path), "polygon.json nao deveria existir antes");

        // Sem OWNER_ADDRESS (zero): recusa.
        vm.setEnv("OWNER_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.expectRevert("Defina OWNER_ADDRESS (carteira dona da Factory)");
        script.run();

        // Rede errada: recusa, mesmo com dono válido.
        vm.setEnv("OWNER_ADDRESS", vm.toString(OWNER));
        vm.chainId(80002);
        vm.expectRevert("So Polygon PoS (chainId 137)");
        script.run();
        vm.chainId(137);

        // Dono = quem assina: recusa (no teste, quem assina é a conta padrão do Foundry).
        vm.setEnv("OWNER_ADDRESS", vm.toString(DEFAULT_SENDER));
        vm.expectRevert("OWNER_ADDRESS nao pode ser o Deployer");
        script.run();
        vm.stopBroadcast(); // o script já tinha aberto o envio quando parou (só acontece em teste)

        // Tudo certo: roda até o fim em simulação (sem --broadcast): não envia nada e não grava arquivo.
        vm.setEnv("OWNER_ADDRESS", vm.toString(OWNER));
        script.run();
        assertFalse(vm.exists(path), "simulacao nao pode gravar polygon.json");
    }
}
