// SPDX-License-Identifier: GPL-2.0-or-later
// Modified by KAMBIODEX (Oct 2026): identifiers renamed (Uniswap* -> Kambiodex*); no logic changes. See CHANGES.md and NOTICE.md.
pragma solidity >=0.5.0;

/// @title Callback for IKambiodexPoolActions#flash
/// @notice Any contract that calls IKambiodexPoolActions#flash must implement this interface
interface IKambiodexFlashCallback {
    /// @notice Called to `msg.sender` after transferring to the recipient from IKambiodexPool#flash.
    /// @dev In the implementation you must repay the pool the tokens sent by flash plus the computed fee amounts.
    /// The caller of this method must be checked to be a KambiodexPool deployed by the canonical KambiodexFactory.
    /// @param fee0 The fee amount in token0 due to the pool by the end of the flash
    /// @param fee1 The fee amount in token1 due to the pool by the end of the flash
    /// @param data Any data passed through by the caller via the IKambiodexPoolActions#flash call
    function kambiodexFlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external;
}
