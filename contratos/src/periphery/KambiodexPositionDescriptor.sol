// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungibleTokenPositionDescriptor.sol';
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import 'base64-sol/base64.sol';

/// @title KambiodexPositionDescriptor
/// @notice Gera o tokenURI (JSON + SVG, tudo on-chain) das posições de liquidez da KAMBIODEX.
/// @dev Escrito do zero. Regras:
///      - nunca dá revert por causa de um token estranho (sem symbol(), symbol em bytes32, lixo no retorno);
///      - todo texto vindo de token é filtrado (só letras, números e alguns sinais), então um token
///        malicioso não consegue injetar JSON ou SVG no metadado;
///      - o token embrulhado (WPOL) aparece com o rótulo da moeda nativa (POL).
contract KambiodexPositionDescriptor is INonfungibleTokenPositionDescriptor {
    /// Token embrulhado da rede (WPOL na Polygon, WBNB na BNB Chain).
    address public immutable WETH9;
    /// Rótulo da moeda nativa mostrado no lugar do token embrulhado (ex.: "POL"), até 32 caracteres.
    bytes32 public immutable nativeLabel;

    uint256 private constant MAX_SYMBOL = 12;
    uint256 private constant MAX_DECIMALS = 36;
    uint256 private constant Q128 = 1 << 128;

    struct Info {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        address pool;
        int24 tickCurrent;
        int24 spacing;
        bool flip; // true: o token base é o token1 (WPOL), preço = token0 por token1
        string quoteSymbol;
        string baseSymbol;
        string minText;
        string maxText;
    }

    constructor(address _WETH9, bytes32 _nativeLabel) {
        WETH9 = _WETH9;
        nativeLabel = _nativeLabel;
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    function tokenURI(INonfungiblePositionManager positionManager, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        Info memory i;
        {
            (, , address t0, address t1, uint24 fee, int24 lo, int24 hi, uint128 liq, , , , ) =
                positionManager.positions(tokenId);
            i.token0 = t0;
            i.token1 = t1;
            i.fee = fee;
            i.tickLower = lo;
            i.tickUpper = hi;
            i.liquidity = liq;
            i.pool = PoolAddress.computeAddress(
                positionManager.factory(),
                PoolAddress.PoolKey({token0: t0, token1: t1, fee: fee})
            );
        }
        (i.tickCurrent, i.spacing) = _poolState(i.pool);

        // Nome do par: QUOTE/BASE. O WPOL é sempre a base (preço em "quantos do outro por 1 POL").
        i.flip = i.token1 == WETH9 && i.token0 != WETH9;
        i.baseSymbol = _symbol(i.flip ? i.token1 : i.token0);
        i.quoteSymbol = _symbol(i.flip ? i.token0 : i.token1);
        (i.minText, i.maxText) = _rangeTexts(i);

        string memory name = _name(i);
        string memory image = Base64.encode(bytes(_svg(tokenId, i)));
        string memory json =
            string(
                abi.encodePacked(
                    '{"name":"', name,
                    '","description":"', _description(i),
                    '","image":"data:image/svg+xml;base64,', image, '"}'
                )
            );
        return string(abi.encodePacked('data:application/json;base64,', Base64.encode(bytes(json))));
    }

    // ------------------------------------------------------------------ textos

    function _name(Info memory i) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    'KAMBIODEX V3 Position - ', _feeText(i.fee), ' - ', i.quoteSymbol, '/', i.baseSymbol,
                    ' - ', i.minText, '<>', i.maxText
                )
            );
    }

    function _description(Info memory i) private pure returns (string memory) {
        string memory intro =
            string(
                abi.encodePacked(
                    'Posicao de liquidez KAMBIODEX V3 no par ', i.quoteSymbol, '/', i.baseSymbol,
                    ', taxa de ', _feeText(i.fee), '. Quem detem este NFT controla a posicao: pode aumentar,',
                    ' reduzir, coletar as taxas ou encerrar a liquidez.'
                )
            );
        string memory addrs =
            string(
                abi.encodePacked(
                    '\\n\\nContrato da pool: ', _hex(i.pool),
                    '\\nEndereco do token 0: ', _hex(i.token0),
                    '\\nEndereco do token 1: ', _hex(i.token1)
                )
            );
        return
            string(
                abi.encodePacked(
                    intro, addrs,
                    '\\n\\nATENCAO: qualquer pessoa pode criar um token com o mesmo nome ou simbolo de outro.',
                    ' Antes de comprar, vender ou negociar este NFT, compare os enderecos dos tokens acima',
                    ' com os enderecos oficiais.'
                )
            );
    }

    function _svg(uint256 tokenId, Info memory i) private pure returns (string memory) {
        string memory head =
            string(
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350" viewBox="0 0 350 350">',
                    '<rect width="350" height="350" fill="#10233F"/>',
                    '<rect x="12" y="12" width="326" height="326" fill="none" stroke="#D9B26A" stroke-width="2"/>',
                    '<g font-family="Arial,Helvetica,sans-serif" fill="#F3F5F8">',
                    '<text x="28" y="56" font-size="22" font-weight="700" fill="#D9B26A" letter-spacing="3">KAMBIODEX</text>',
                    '<text x="28" y="80" font-size="12" letter-spacing="2">V3 POSITION</text>'
                )
            );
        string memory pair =
            string(
                abi.encodePacked(
                    '<text x="28" y="150" font-size="30" font-weight="700">', i.quoteSymbol, '/', i.baseSymbol, '</text>',
                    '<text x="28" y="180" font-size="16" fill="#D9B26A">', _feeText(i.fee), '</text>'
                )
            );
        string memory range =
            string(
                abi.encodePacked(
                    '<text x="28" y="240" font-size="12" opacity="0.7">MIN</text>',
                    '<text x="28" y="260" font-size="16">', i.minText, '</text>',
                    '<text x="28" y="288" font-size="12" opacity="0.7">MAX</text>',
                    '<text x="28" y="308" font-size="16">', i.maxText, '</text>'
                )
            );
        string memory tail =
            string(
                abi.encodePacked(
                    '<text x="322" y="56" font-size="14" text-anchor="end">#', _uint(tokenId), '</text>',
                    '<text x="322" y="308" font-size="13" text-anchor="end" fill="#D9B26A">', _status(i), '</text>',
                    '</g></svg>'
                )
            );
        return string(abi.encodePacked(head, pair, range, tail));
    }

    function _status(Info memory i) private pure returns (string memory) {
        if (i.liquidity == 0) return 'CLOSED';
        return i.tickCurrent >= i.tickLower && i.tickCurrent < i.tickUpper ? 'IN RANGE' : 'OUT OF RANGE';
    }

    /// 100 -> "0,01%", 500 -> "0,05%", 3000 -> "0,3%", 10000 -> "1%".
    function _feeText(uint24 fee) private pure returns (string memory) {
        uint256 whole = fee / 10000;
        uint256 frac = fee % 10000; // 4 casas
        if (frac == 0) return string(abi.encodePacked(_uint(whole), '%'));
        bytes memory digits = new bytes(4);
        for (uint256 k = 0; k < 4; k++) {
            digits[3 - k] = bytes1(uint8(48 + (frac % 10)));
            frac /= 10;
        }
        uint256 len = 4;
        while (len > 0 && digits[len - 1] == '0') len--;
        bytes memory trimmed = new bytes(len);
        for (uint256 k = 0; k < len; k++) trimmed[k] = digits[k];
        return string(abi.encodePacked(_uint(whole), ',', trimmed, '%'));
    }

    // ------------------------------------------------------------------ faixa de preço

    /// Textos do preço mínimo e máximo da faixa, na unidade "QUOTE por 1 BASE".
    /// Pontas extremas viram "MIN"/"MAX"; um preço que não cabe nas contas vira "N/A" (nunca dá revert).
    function _rangeTexts(Info memory i) private view returns (string memory minText, string memory maxText) {
        // quando o par é invertido, o menor preço exibido vem do tick MAIS ALTO.
        int24 tickForMin = i.flip ? i.tickUpper : i.tickLower;
        int24 tickForMax = i.flip ? i.tickLower : i.tickUpper;
        (uint8 dec0, uint8 dec1) = (_decimals(i.token0), _decimals(i.token1));

        minText = _edgeText(tickForMin, i.spacing, i.flip, dec0, dec1);
        maxText = _edgeText(tickForMax, i.spacing, i.flip, dec0, dec1);
    }

    function _edgeText(int24 tick, int24 spacing, bool flip, uint8 dec0, uint8 dec1)
        private
        view
        returns (string memory)
    {
        // Ponta extrema = menor/maior tick utilizável da faixa de taxa (faixa completa).
        // Sem o espaçamento (pool ilegível) não dá para saber: usa os limites absolutos.
        int24 usableMin = spacing > 0 ? (TickMath.MIN_TICK / spacing) * spacing : TickMath.MIN_TICK;
        int24 usableMax = spacing > 0 ? (TickMath.MAX_TICK / spacing) * spacing : TickMath.MAX_TICK;
        if (tick <= usableMin) return flip ? 'MAX' : 'MIN';
        if (tick >= usableMax) return flip ? 'MIN' : 'MAX';

        try this.priceText(tick, flip, dec0, dec1) returns (string memory t) {
            return t;
        } catch {
            return 'N/A';
        }
    }

    /// Preço do tick como texto decimal. Externa só para que o chamador possa usar try/catch.
    function priceText(int24 tick, bool flip, uint8 dec0, uint8 dec1) external pure returns (string memory) {
        uint256 d0 = dec0 > MAX_DECIMALS ? MAX_DECIMALS : dec0;
        uint256 d1 = dec1 > MAX_DECIMALS ? MAX_DECIMALS : dec1;
        uint256 sqrtP = TickMath.getSqrtRatioAtTick(tick);
        uint256 p128 = FullMath.mulDiv(sqrtP, sqrtP, 1 << 64); // token1/token0 (bruto) * 2^128
        require(p128 > 0, 'preco zero');

        // 8 casas decimais de precisão: valor = preço_humano * 1e8
        uint256 scaled;
        if (!flip) {
            // humano = bruto * 10^d0 / 10^d1
            scaled = FullMath.mulDiv(p128, 10**(d0 + 8), (10**d1) << 128);
        } else {
            // humano = (1/bruto) * 10^d1 / 10^d0 = 2^128 * 10^d1 / (p128 * 10^d0)
            uint256 inv128 = FullMath.mulDiv(Q128, Q128, p128);
            scaled = FullMath.mulDiv(inv128, 10**(d1 + 8), (10**d0) << 128);
        }
        return _decimalText(scaled);
    }

    /// `scaled` tem 8 casas implícitas. Mostra 4 casas se o preço é >= 1; abaixo de 1, 4 algarismos
    /// significativos depois dos zeros iniciais (até 8 casas). Zeros finais saem.
    function _decimalText(uint256 scaled) private pure returns (string memory) {
        if (scaled == 0) return '<0.00000001';
        uint256 whole = scaled / 1e8;
        uint256 frac = scaled % 1e8;
        uint256 places = 4;
        if (whole == 0) {
            uint256 zeros;
            while (zeros < 4 && frac < 10**(7 - zeros)) zeros++;
            places = zeros + 4;
        }
        frac /= 10**(8 - places);
        while (places > 0 && frac % 10 == 0) {
            frac /= 10;
            places--;
        }
        if (places == 0) return _uint(whole);
        bytes memory f = new bytes(places);
        for (uint256 k = 0; k < places; k++) {
            f[places - 1 - k] = bytes1(uint8(48 + (frac % 10)));
            frac /= 10;
        }
        return string(abi.encodePacked(_uint(whole), '.', f));
    }

    // ------------------------------------------------------------------ leitura segura

    function _poolState(address pool) private view returns (int24 tick, int24 spacing) {
        try IUniswapV3Pool(pool).slot0() returns (uint160, int24 t, uint16, uint16, uint16, uint8, bool) {
            tick = t;
        } catch {}
        try IUniswapV3Pool(pool).tickSpacing() returns (int24 s) {
            spacing = s;
        } catch {}
    }

    function _decimals(address token) private view returns (uint8) {
        if (token == WETH9) return 18;
        (bool ok, bytes memory ret) = token.staticcall{gas: 50000}(abi.encodeWithSelector(0x313ce567));
        if (!ok || ret.length != 32) return 18;
        uint256 v = abi.decode(ret, (uint256));
        return v > MAX_DECIMALS ? 18 : uint8(v);
    }

    /// Símbolo seguro: nunca reverte, filtra caracteres, limita o tamanho.
    /// Sem símbolo legível -> endereço abreviado (0x1234…abcd).
    function _symbol(address token) private view returns (string memory) {
        if (token == WETH9) return _clean(abi.encodePacked(nativeLabel));
        (bool ok, bytes memory ret) = token.staticcall{gas: 50000}(abi.encodeWithSelector(0x95d89b41));
        bytes memory raw;
        if (ok) {
            if (ret.length == 32) {
                raw = ret; // formato antigo: bytes32 (ex.: MKR)
            } else if (ret.length >= 96) {
                uint256 offset;
                assembly {
                    offset := mload(add(ret, 32))
                }
                if (offset <= ret.length - 32) {
                    uint256 len;
                    assembly {
                        len := mload(add(add(ret, 32), offset))
                    }
                    if (len <= ret.length - 32 - offset) {
                        raw = new bytes(len);
                        for (uint256 k = 0; k < len; k++) raw[k] = ret[offset + 32 + k];
                    }
                }
            }
        }
        string memory s = _clean(raw);
        if (bytes(s).length == 0) return _shortAddress(token);
        return s;
    }

    /// Mantém só A-Z a-z 0-9 e . - _ $ + (para na primeira letra inválida de fim de texto = byte 0).
    function _clean(bytes memory raw) private pure returns (string memory) {
        bytes memory out = new bytes(raw.length < MAX_SYMBOL ? raw.length : MAX_SYMBOL);
        uint256 n;
        for (uint256 k = 0; k < raw.length && n < MAX_SYMBOL; k++) {
            bytes1 c = raw[k];
            if (c == 0x00) break;
            bool good = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) ||
                c == '.' || c == '-' || c == '_' || c == '$' || c == '+';
            if (good) out[n++] = c;
        }
        bytes memory trimmed = new bytes(n);
        for (uint256 k = 0; k < n; k++) trimmed[k] = out[k];
        return string(trimmed);
    }

    function _shortAddress(address a) private pure returns (string memory) {
        bytes memory full = bytes(_hex(a)); // "0x" + 40
        bytes memory out = new bytes(11); // "0x1234_abcd" (sem reticências: o "…" não passa no filtro)
        for (uint256 k = 0; k < 6; k++) out[k] = full[k];
        out[6] = '_';
        for (uint256 k = 0; k < 4; k++) out[7 + k] = full[full.length - 4 + k];
        return string(out);
    }

    // ------------------------------------------------------------------ utilidades

    function _uint(uint256 v) private pure returns (string memory) {
        if (v == 0) return '0';
        uint256 digits;
        for (uint256 t = v; t != 0; t /= 10) digits++;
        bytes memory b = new bytes(digits);
        while (v != 0) {
            digits--;
            b[digits] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }

    function _hex(address a) private pure returns (string memory) {
        bytes memory h = '0123456789abcdef';
        bytes memory out = new bytes(42);
        out[0] = '0';
        out[1] = 'x';
        uint160 v = uint160(a);
        for (uint256 k = 0; k < 20; k++) {
            uint8 byt = uint8(v >> (8 * (19 - k)));
            out[2 + 2 * k] = h[byt >> 4];
            out[3 + 2 * k] = h[byt & 0x0f];
        }
        return string(out);
    }
}
