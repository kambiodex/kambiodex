// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @dev ERC-20 "esquisito" para testar o descriptor do NFT: o comportamento de symbol() muda
///      conforme `mode` (e symbol() nem existe como função: cai no fallback).
contract OddToken {
    uint8 public decimals;
    uint8 public mode;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 _mode, uint8 _decimals) {
        mode = _mode;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    /// mode 0: symbol() dá revert | 1: retorna vazio | 2: bytes32 "MKR" | 3: string com aspas/tags (ataque)
    /// mode 4: lixo com deslocamento gigante | 5: comprimento gigante | 6: string longa | 7: só caracteres proibidos
    /// mode 8: string válida de 100.000 bytes (cabe no limite de 50.000 de gás que o descriptor dá à chamada)
    fallback() external {
        require(msg.sig == 0x95d89b41, "so symbol()");
        if (mode == 0) revert("sem symbol");
        if (mode == 1) return;
        if (mode == 8) {
            // ABI de string: deslocamento 32, tamanho 100000, depois 100000 bytes (zeros, memória nunca escrita).
            // Montada direto na memória: só a expansão da memória custa gás (~28 mil).
            assembly {
                mstore(0, 32)
                mstore(32, 100000)
                return(0, add(64, 100000))
            }
        }
        bytes memory out;
        if (mode == 2) {
            out = abi.encode(bytes32("MKR"));
        } else if (mode == 3) {
            out = abi.encode('A","x":"<script>alert(1)</script>');
        } else if (mode == 4) {
            out = abi.encode(uint256(type(uint256).max), uint256(1), uint256(2));
        } else if (mode == 5) {
            out = abi.encode(uint256(32), type(uint256).max, uint256(0));
        } else if (mode == 6) {
            out = abi.encode("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
        } else {
            out = abi.encode('"<>&/\\ ');
        }
        assembly {
            return(add(out, 32), mload(out))
        }
    }
}
