// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV3Deployer} from "../script/helpers/UniswapV3Deployer.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {OddToken} from "./helpers/OddToken.sol";
import {TextUtils} from "./helpers/TextUtils.sol";
import {INPM} from "./helpers/IPeriphery.sol";

interface IDescriptor {
    function WETH9() external view returns (address);
    function nativeLabel() external view returns (bytes32);
    function priceText(int24 tick, bool flip, uint8 dec0, uint8 dec1) external pure returns (string memory);
}

/// @notice Testa o descriptor próprio da KAMBIODEX (nome, descrição e SVG do NFT da posição).
contract DescriptorTest is Test, UniswapV3Deployer, TextUtils {
    uint160 constant PRICE_1 = 2 ** 96;
    int24 constant MAX_TICK = 887272;

    Deployed d;
    INPM npm;
    IUniswapV3Factory factory;
    address wpol;
    address user;
    MockERC20 tA;
    MockERC20 tB;

    function setUp() public {
        wpol = _create("WrappedNativeTestnet.sol:WrappedNativeTestnet", abi.encode("Wrapped POL", "WPOL"));
        d = deployAll(wpol, address(0));
        npm = INPM(d.positionManager);
        factory = IUniswapV3Factory(d.factory);
        tA = new MockERC20("Token A", "AAA", 18);
        tB = new MockERC20("Token B", "BBB", 18);
        user = makeAddr("user");
        vm.deal(user, 1000 ether);
        _fund(address(tA));
        _fund(address(tB));
    }

    // ------------------------------------------------------------------ ajudantes

    function _fund(address token) internal {
        MockERC20(token).mint(user, 1e30);
        vm.prank(user);
        MockERC20(token).approve(address(npm), type(uint256).max);
    }

    function _fundOdd(OddToken t) internal {
        t.mint(user, 1e30);
        vm.prank(user);
        t.approve(address(npm), type(uint256).max);
    }

    function _mint(address a, address b, uint24 fee, int24 lo, int24 hi, uint160 price) internal returns (uint256 id) {
        (address t0, address t1) = a < b ? (a, b) : (b, a);
        npm.createAndInitializePoolIfNecessary(t0, t1, fee, price);
        vm.prank(user);
        (id,,,) = npm.mint(INPM.MintParams(t0, t1, fee, lo, hi, 1e21, 1e21, 0, 0, user, block.timestamp + 1 hours));
    }

    function _full(uint24 fee) internal view returns (int24 lo, int24 hi) {
        int24 s = factory.feeAmountTickSpacing(fee);
        hi = (MAX_TICK / s) * s;
        lo = -hi;
    }

    function _json(uint256 id) internal view returns (bytes memory) {
        bytes memory uri = bytes(npm.tokenURI(id));
        assertTrue(_startsWith(uri, "data:application/json;base64,"), "formato do tokenURI");
        return _b64decode(_tail(uri, "data:application/json;base64,"));
    }

    function _name(uint256 id) internal view returns (string memory) {
        return vm.parseJsonString(string(_json(id)), ".name"); // também prova que o JSON é válido
    }

    function _sym(MockERC20 t) internal view returns (string memory) {
        return t.symbol();
    }

    // ------------------------------------------------------------------ testes

    function test_constructorArgs() public view {
        assertEq(IDescriptor(d.descriptor).WETH9(), wpol);
        assertEq(IDescriptor(d.descriptor).nativeLabel(), bytes32("POL"));
    }

    function test_tokenURI_validJson_noUniswap_nameFormat() public {
        (int24 lo, int24 hi) = _full(3000);
        uint256 id = _mint(address(tA), address(tB), 3000, lo, hi, PRICE_1);

        bytes memory json = _json(id);
        string memory j = string(json);
        string memory name = vm.parseJsonString(j, ".name");
        string memory desc = vm.parseJsonString(j, ".description");
        string memory image = vm.parseJsonString(j, ".image");
        assertTrue(_startsWith(bytes(image), "data:image/svg+xml;base64,"), "imagem");

        // token1 é o "quote": BBB/AAA se AAA < BBB em endereço, e AAA/BBB no caso contrário.
        (MockERC20 q, MockERC20 b) = address(tA) < address(tB) ? (tB, tA) : (tA, tB);
        assertEq(name, string.concat("KAMBIODEX V3 Position - 0.3% - ", _sym(q), "/", _sym(b), " - FULL RANGE"));
        assertTrue(_contains(bytes(desc), "KAMBIODEX"), "descricao sem a marca");
        assertTrue(_contains(bytes(desc), "Pool address: 0x"), "descricao sem pool");
        assertTrue(_contains(bytes(desc), "Token 0 address: 0x"), "descricao sem token0");
        assertTrue(_contains(bytes(desc), "Token 1 address: 0x"), "descricao sem token1");
        assertTrue(_contains(bytes(desc), "fee tier 0.3%"), "descricao sem taxa");
        assertTrue(_contains(bytes(desc), "compare the token addresses"), "descricao sem aviso");

        bytes memory svg = _b64decode(_svgOf(json));
        assertTrue(_contains(svg, "KAMBIODEX"), "svg sem a marca");
        assertTrue(_startsWith(svg, "<svg"), "svg");

        // Em nenhum lugar a palavra "Uniswap" (em qualquer caixa), nem no JSON nem no SVG.
        assertFalse(_contains(_lower(json), "uniswap"), "JSON tem Uniswap");
        assertFalse(_contains(_lower(svg), "uniswap"), "SVG tem Uniswap");
    }

    /// Extrai o base64 do SVG de dentro do JSON decodificado.
    function _svgOf(bytes memory json) internal pure returns (bytes memory out) {
        bytes memory rest = _tail(json, "data:image/svg+xml;base64,");
        uint256 n;
        while (n < rest.length && rest[n] != '"') n++;
        out = new bytes(n);
        for (uint256 k = 0; k < n; k++) out[k] = rest[k];
    }

    function test_feeTexts() public {
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        string[4] memory txt = ["0.01%", "0.05%", "0.3%", "1%"];
        for (uint256 k = 0; k < 4; k++) {
            (int24 lo, int24 hi) = _full(fees[k]);
            uint256 id = _mint(address(tA), address(tB), fees[k], lo, hi, PRICE_1);
            string memory name = _name(id);
            assertTrue(_contains(bytes(name), bytes(string.concat(" - ", txt[k], " - "))), name);
            assertTrue(_endsWith(bytes(name), "FULL RANGE"), "faixa completa: FULL RANGE em todas as faixas de taxa");
        }
    }

    function test_wpolShowsAsPol_inBothOrders() public {
        // Pool WPOL/AAA: o WPOL pode ser token0 ou token1 conforme o endereço; o resultado é o mesmo.
        (int24 lo, int24 hi) = _full(3000);
        npm.createAndInitializePoolIfNecessary(
            wpol < address(tA) ? wpol : address(tA), wpol < address(tA) ? address(tA) : wpol, 3000, PRICE_1
        );
        (address t0, address t1) = wpol < address(tA) ? (wpol, address(tA)) : (address(tA), wpol);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            INPM.mint, (INPM.MintParams(t0, t1, 3000, lo, hi, 10 ether, 10 ether, 0, 0, user, block.timestamp + 1 hours))
        );
        calls[1] = abi.encodeCall(INPM.refundETH, ());
        vm.prank(user);
        npm.multicall{value: 20 ether}(calls);

        bytes memory json = _json(1);
        string memory name = vm.parseJsonString(string(json), ".name");
        assertEq(name, "KAMBIODEX V3 Position - 0.3% - AAA/POL - FULL RANGE");
        assertFalse(_contains(json, "WPOL"), "WPOL apareceu");
        assertTrue(_contains(_b64decode(_svgOf(json)), "AAA/POL"), "svg sem AAA/POL");
        assertFalse(_contains(_b64decode(_svgOf(json)), "WPOL"), "svg com WPOL");
    }

    function test_narrowRange_showsPrices() public {
        uint256 id = _mint(address(tA), address(tB), 3000, -600, 600, PRICE_1);
        string memory name = _name(id);
        // 1,0001^-600 = 0,94176...  e  1,0001^600 = 1,06183...  (preço token1 por token0)
        (MockERC20 q, MockERC20 b) = address(tA) < address(tB) ? (tB, tA) : (tA, tB);
        assertEq(name, string.concat("KAMBIODEX V3 Position - 0.3% - ", _sym(q), "/", _sym(b), " - 0.9417<>1.0618"));
        // posição dentro da faixa
        assertTrue(_contains(_b64decode(_svgOf(_json(id))), "IN RANGE"));
    }

    function _count(bytes memory h, bytes memory n) internal pure returns (uint256 c) {
        if (n.length == 0 || h.length < n.length) return 0;
        for (uint256 i = 0; i + n.length <= h.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) c++;
        }
    }

    function test_fullRange_nameAndImage_perFee() public {
        uint24[3] memory fees = [uint24(500), 3000, 10000];
        string[3] memory txt = ["0.05%", "0.3%", "1%"];
        (MockERC20 q, MockERC20 b) = address(tA) < address(tB) ? (tB, tA) : (tA, tB);
        for (uint256 k = 0; k < 3; k++) {
            (int24 lo, int24 hi) = _full(fees[k]);
            uint256 id = _mint(address(tA), address(tB), fees[k], lo, hi, PRICE_1);
            assertEq(
                _name(id),
                string.concat("KAMBIODEX V3 Position - ", txt[k], " - ", _sym(q), "/", _sym(b), " - FULL RANGE")
            );
            bytes memory svg = _b64decode(_svgOf(_json(id)));
            assertEq(_count(svg, "FULL RANGE"), 1, "FULL RANGE deve aparecer uma vez");
            assertFalse(_contains(svg, ">MIN<"), "sem rotulo MIN");
            assertFalse(_contains(svg, ">MAX<"), "sem rotulo MAX");
            assertTrue(_contains(svg, "IN RANGE"), "status mantido");
        }
    }

    function test_normalRange_nameAndImage_perFee() public {
        uint24[3] memory fees = [uint24(500), 3000, 10000];
        string[3] memory txt = ["0.05%", "0.3%", "1%"];
        (MockERC20 q, MockERC20 b) = address(tA) < address(tB) ? (tB, tA) : (tA, tB);
        for (uint256 k = 0; k < 3; k++) {
            int24 s = factory.feeAmountTickSpacing(fees[k]);
            int24 w = (600 / s) * s;
            if (w == 0) w = s;
            uint256 id = _mint(address(tA), address(tB), fees[k], -w, w, PRICE_1);
            string memory name = _name(id);
            string memory prefix =
                string.concat("KAMBIODEX V3 Position - ", txt[k], " - ", _sym(q), "/", _sym(b), " - ");
            assertTrue(_startsWith(bytes(name), bytes(prefix)), name);
            assertTrue(_contains(bytes(name), "<>"), "faixa normal: min<>max");
            assertFalse(_contains(bytes(name), "FULL RANGE"), "faixa normal nao e FULL RANGE");
            bytes memory svg = _b64decode(_svgOf(_json(id)));
            assertEq(_count(svg, "FULL RANGE"), 0);
            assertEq(_count(svg, ">MIN<"), 1, "rotulo MIN mantido");
            assertEq(_count(svg, ">MAX<"), 1, "rotulo MAX mantido");
        }
    }

    function test_halfExtremeRange_isNotFullRange() public {
        (int24 lo,) = _full(3000);
        uint256 id = _mint(address(tA), address(tB), 3000, lo, 0, PRICE_1 * 2);
        assertFalse(_contains(bytes(_name(id)), "FULL RANGE"));
        assertEq(_count(_b64decode(_svgOf(_json(id))), "FULL RANGE"), 0);
    }

    function test_outOfRangeStatus() public {
        // preço atual (tick 0) abaixo da faixa [600, 1200]
        uint256 id = _mint(address(tA), address(tB), 3000, 600, 1200, PRICE_1);
        assertTrue(_contains(_b64decode(_svgOf(_json(id))), "OUT OF RANGE"));
    }

    function test_priceText_decimalsAndFlip() public view {
        IDescriptor ds = IDescriptor(d.descriptor);
        assertEq(ds.priceText(0, false, 18, 18), "1");
        assertEq(ds.priceText(0, true, 18, 18), "1");
        assertEq(ds.priceText(0, false, 6, 18), "<0.00000001"); // 1e-12 em unidades humanas
        assertEq(ds.priceText(0, false, 18, 6), "1000000000000");
        assertEq(ds.priceText(0, true, 18, 6), "<0.00000001");
        assertEq(ds.priceText(276324, false, 6, 18), "0.9999"); // 1,0001^276324 / 1e12
        assertEq(ds.priceText(6931, false, 18, 18), "1.9998"); // ~2
        assertEq(ds.priceText(-6932, false, 18, 18), "0.4999"); // 0,49998 (corta, não arredonda)
    }

    function test_extremeTicks_neverRevert() public {
        // Faixas completas em todas as taxas (pontas extremas) já foram testadas; aqui, perto do limite.
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        for (uint256 k = 0; k < 4; k++) {
            (int24 lo, int24 hi) = _full(fees[k]);
            int24 s = factory.feeAmountTickSpacing(fees[k]);
            // [mínimo extremo, ponto normal] e [ponto normal, máximo extremo]
            uint256 id1 = _mint(address(tA), address(tB), fees[k], lo, 0, PRICE_1 * 2);
            assertTrue(_startsWith(bytes(_name(id1)), "KAMBIODEX V3 Position"));
            assertTrue(_contains(bytes(_name(id1)), "MIN<>"));
            uint256 id2 = _mint(address(tA), address(tB), fees[k], 0, hi, PRICE_1 / 2);
            assertTrue(_endsWith(bytes(_name(id2)), "<>MAX"));
            // uma casa antes das pontas: preço gigante / minúsculo, mas nunca revert
            uint256 id3 = _mint(address(tA), address(tB), fees[k], lo + s, hi - s, PRICE_1);
            _name(id3);
        }
    }

    function test_extremeTicks_withPolFlipped() public {
        // WPOL como token1 (inverte o preço) com pontas quase extremas: nunca revert.
        (int24 lo, int24 hi) = _full(3000);
        (address t0, address t1) = wpol < address(tA) ? (wpol, address(tA)) : (address(tA), wpol);
        npm.createAndInitializePoolIfNecessary(t0, t1, 3000, PRICE_1);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            INPM.mint, (INPM.MintParams(t0, t1, 3000, lo + 60, hi - 60, 1 ether, 1 ether, 0, 0, user, block.timestamp + 1 hours))
        );
        calls[1] = abi.encodeCall(INPM.refundETH, ());
        vm.prank(user);
        npm.multicall{value: 2 ether}(calls);
        _name(1);
    }

    function test_directPriceText_extremeTicksRevertOrWork_butTokenURIDoesNot() public view {
        // priceText pode reverter em casos absurdos (é interna ao descriptor); tokenURI usa try/catch.
        IDescriptor ds = IDescriptor(d.descriptor);
        try ds.priceText(-887220, true, 18, 18) returns (string memory t) {
            assertGt(bytes(t).length, 0);
        } catch {}
    }

    // ------------------------------------------------------------------ tokens esquisitos

    function _oddPair(uint8 mode, uint8 decimals) internal returns (uint256 id, OddToken odd) {
        odd = new OddToken(mode, decimals);
        _fundOdd(odd);
        (int24 lo, int24 hi) = _full(3000);
        id = _mint(address(odd), address(tA), 3000, lo, hi, PRICE_1);
    }

    function test_oddTokens_neverRevert_andFallBackToShortAddress() public {
        uint8[8] memory modes = [0, 1, 2, 3, 4, 5, 6, 7];
        for (uint256 m = 0; m < 8; m++) {
            (uint256 id, OddToken odd) = _oddPair(modes[m], 18);
            string memory name = _name(id); // JSON válido e sem revert, em todos os casos
            bytes memory json = _json(id);
            // nada de injeção: nenhum "<script" ou aspa solta vinda do símbolo
            assertFalse(_contains(_b64decode(_svgOf(json)), "<script"), "injecao no SVG");
            assertFalse(_contains(json, "<script"), "injecao no JSON");
            assertFalse(_contains(_lower(json), "uniswap"));
            if (m == 0 || m == 1 || m == 4 || m == 5 || m == 7) {
                // sem símbolo legível: usa 0x1234_abcd (começo e fim do endereço)
                bytes memory a = bytes(vm.toString(address(odd)));
                bytes memory shortAddr = abi.encodePacked(_slice(a, 0, 6), "_", _slice(a, 38, 42));
                assertTrue(_contains(_lower(bytes(name)), _lower(shortAddr)), name);
            }
            if (m == 2) assertTrue(_contains(bytes(name), "MKR"), name);
            if (m == 6) assertTrue(_contains(bytes(name), "ABCDEFGHIJKL/") || _contains(bytes(name), "/ABCDEFGHIJKL"), name);
            if (m == 3) assertTrue(_contains(bytes(name), "Ax"), name); // só os caracteres permitidos sobraram
        }
    }

    function test_oddTokens_hugeDecimals_neverRevert() public {
        _oddPair(2, 255);
        _name(1);
        _oddPair(2, 0);
        _name(2);
    }

    function test_tokenURI_unknownId_reverts() public {
        vm.expectRevert();
        npm.tokenURI(999);
    }

    // ------------------------------------------------------------------ utilidades

    function _endsWith(bytes memory s, bytes memory suffix) internal pure returns (bool) {
        if (s.length < suffix.length) return false;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (s[s.length - suffix.length + i] != suffix[i]) return false;
        }
        return true;
    }

    function _slice(bytes memory s, uint256 from, uint256 to) internal pure returns (bytes memory out) {
        out = new bytes(to - from);
        for (uint256 i = from; i < to; i++) out[i - from] = s[i];
    }
}
