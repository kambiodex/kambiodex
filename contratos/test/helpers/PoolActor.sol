// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {IKambiodexPool} from "@kambiodex/core/interfaces/IKambiodexPool.sol";
import {IKambiodexMintCallback} from "@kambiodex/core/interfaces/callback/IKambiodexMintCallback.sol";
import {IKambiodexSwapCallback} from "@kambiodex/core/interfaces/callback/IKambiodexSwapCallback.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Contrato "carteira" para falar direto com a pool nos testes: paga nos callbacks de
///      depósito (mint) e de troca (swap). Cada instância é um usuário diferente (dono da posição).
contract PoolActor is IKambiodexMintCallback, IKambiodexSwapCallback {
    function mint(IKambiodexPool pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(pool));
    }

    function burn(IKambiodexPool pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return pool.burn(tickLower, tickUpper, liquidity);
    }

    function collect(IKambiodexPool pool, int24 tickLower, int24 tickUpper, address to)
        external
        returns (uint128 amount0, uint128 amount1)
    {
        return pool.collect(to, tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    function swap(IKambiodexPool pool, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96)
        external
        returns (int256 amount0, int256 amount1)
    {
        return pool.swap(address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, abi.encode(pool));
    }

    function kambiodexMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        IKambiodexPool pool = abi.decode(data, (IKambiodexPool));
        require(msg.sender == address(pool), "callback: so a pool");
        if (amount0Owed > 0) MockERC20(pool.token0()).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) MockERC20(pool.token1()).transfer(msg.sender, amount1Owed);
    }

    function kambiodexSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        IKambiodexPool pool = abi.decode(data, (IKambiodexPool));
        require(msg.sender == address(pool), "callback: so a pool");
        if (amount0Delta > 0) MockERC20(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) MockERC20(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
    }
}
