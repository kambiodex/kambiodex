// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @dev Utilitários de texto só para os testes do NFT (decodificar base64, procurar trechos).
abstract contract TextUtils {
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

    function _lower(bytes memory s) internal pure returns (bytes memory out) {
        out = new bytes(s.length);
        for (uint256 i = 0; i < s.length; i++) {
            uint8 c = uint8(s[i]);
            out[i] = (c >= 65 && c <= 90) ? bytes1(c + 32) : s[i];
        }
    }

    function _startsWith(bytes memory s, bytes memory prefix) internal pure returns (bool) {
        if (s.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (s[i] != prefix[i]) return false;
        }
        return true;
    }

    /// Texto depois de `marker` (que precisa existir).
    function _tail(bytes memory text, bytes memory marker) internal pure returns (bytes memory out) {
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
            out = new bytes(text.length - start);
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
