// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './pool/IKambiodexPoolImmutables.sol';
import './pool/IKambiodexPoolState.sol';
import './pool/IKambiodexPoolDerivedState.sol';
import './pool/IKambiodexPoolActions.sol';
import './pool/IKambiodexPoolOwnerActions.sol';
import './pool/IKambiodexPoolEvents.sol';

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IKambiodexPool is
    IKambiodexPoolImmutables,
    IKambiodexPoolState,
    IKambiodexPoolDerivedState,
    IKambiodexPoolActions,
    IKambiodexPoolOwnerActions,
    IKambiodexPoolEvents
{

}
