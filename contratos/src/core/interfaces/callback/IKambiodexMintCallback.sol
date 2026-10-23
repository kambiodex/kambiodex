// SPDX-License-Identifier: GPL-2.0-or-later
// Modified by KAMBIODEX (Oct 2026): identifiers renamed (Uniswap* -> Kambiodex*); no logic changes. See CHANGES.md and NOTICE.md.
pragma solidity >=0.5.0;

/// @title Callback for IKambiodexPoolActions#mint
/// @notice Any contract that calls IKambiodexPoolActions#mint must implement this interface
interface IKambiodexMintCallback {
    /// @notice Called to `msg.sender` after minting liquidity to a position from IKambiodexPool#mint.
    /// @dev In the implementation you must pay the pool tokens owed for the minted liquidity.
    /// The caller of this method must be checked to be a KambiodexPool deployed by the canonical KambiodexFactory.
    /// @param amount0Owed The amount of token0 due to the pool for the minted liquidity
    /// @param amount1Owed The amount of token1 due to the pool for the minted liquidity
    /// @param data Any data passed through by the caller via the IKambiodexPoolActions#mint call
    function kambiodexMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}
