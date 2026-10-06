// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Contrato "carteira" para falar direto com a pool nos testes: paga nos callbacks de
///      depósito (mint) e de troca (swap). Cada instância é um usuário diferente (dono da posição).
contract PoolActor is IUniswapV3MintCallback, IUniswapV3SwapCallback {
    function mint(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(pool));
    }

    function burn(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return pool.burn(tickLower, tickUpper, liquidity);
    }

    function collect(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, address to)
        external
        returns (uint128 amount0, uint128 amount1)
    {
        return pool.collect(to, tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    function swap(IUniswapV3Pool pool, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96)
        external
        returns (int256 amount0, int256 amount1)
    {
        return pool.swap(address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, abi.encode(pool));
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        IUniswapV3Pool pool = abi.decode(data, (IUniswapV3Pool));
        require(msg.sender == address(pool), "callback: so a pool");
        if (amount0Owed > 0) MockERC20(pool.token0()).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) MockERC20(pool.token1()).transfer(msg.sender, amount1Owed);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        IUniswapV3Pool pool = abi.decode(data, (IUniswapV3Pool));
        require(msg.sender == address(pool), "callback: so a pool");
        if (amount0Delta > 0) MockERC20(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) MockERC20(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
    }
}
