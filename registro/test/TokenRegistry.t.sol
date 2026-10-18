// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenRegistry.sol";

contract TokenRegistryTest is Test {
    TokenRegistry r;
    address owner = address(0xA11CE);
    address other = address(0xB0B);
    address t1 = address(0x1001);
    address t2 = address(0x1002);

    function setUp() public {
        r = new TokenRegistry(owner);
    }

    function test_ownerIsSet() public view {
        assertEq(r.owner(), owner);
    }

    function test_constructorRejectsZero() public {
        vm.expectRevert(TokenRegistry.ZeroAddress.selector);
        new TokenRegistry(address(0));
    }

    function test_defaultIsNone() public view {
        assertEq(r.statusOf(t1), 0);
    }

    function test_ownerCanListAndBlock() public {
        vm.startPrank(owner);
        r.setStatus(t1, 1);
        r.setStatus(t2, 2);
        vm.stopPrank();
        assertEq(r.statusOf(t1), 1);
        assertEq(r.statusOf(t2), 2);
        assertEq(r.count(), 2);
    }

    function test_removeKeepsSingleEntry() public {
        vm.startPrank(owner);
        r.setStatus(t1, 1);
        r.setStatus(t1, 0);
        r.setStatus(t1, 2);
        vm.stopPrank();
        assertEq(r.count(), 1);
        assertEq(r.statusOf(t1), 2);
    }

    function test_nonOwnerCannotWrite() public {
        vm.prank(other);
        vm.expectRevert(TokenRegistry.NotOwner.selector);
        r.setStatus(t1, 1);
    }

    function test_rejectsBadStatusAndZeroToken() public {
        vm.startPrank(owner);
        vm.expectRevert(TokenRegistry.BadStatus.selector);
        r.setStatus(t1, 3);
        vm.expectRevert(TokenRegistry.ZeroAddress.selector);
        r.setStatus(address(0), 1);
        vm.stopPrank();
    }

    function test_batchAndStatuses() public {
        address[] memory a = new address[](2);
        uint8[] memory s = new uint8[](2);
        a[0] = t1; a[1] = t2; s[0] = 1; s[1] = 2;
        vm.prank(owner);
        r.setStatusBatch(a, s);
        uint8[] memory out = r.statuses(a);
        assertEq(out[0], 1);
        assertEq(out[1], 2);
    }

    function test_batchLengthMismatch() public {
        address[] memory a = new address[](2);
        uint8[] memory s = new uint8[](1);
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.LengthMismatch.selector);
        r.setStatusBatch(a, s);
    }

    function test_page() public {
        vm.startPrank(owner);
        r.setStatus(t1, 1);
        r.setStatus(t2, 2);
        vm.stopPrank();
        (address[] memory toks, uint8[] memory sts) = r.page(0, 10);
        assertEq(toks.length, 2);
        assertEq(toks[1], t2);
        assertEq(sts[1], 2);
        (toks, sts) = r.page(5, 10);
        assertEq(toks.length, 0);
    }

    function test_twoStepOwnership() public {
        vm.prank(owner);
        r.transferOwnership(other);
        assertEq(r.owner(), owner);
        vm.prank(t1);
        vm.expectRevert(TokenRegistry.NotPendingOwner.selector);
        r.acceptOwnership();
        vm.prank(other);
        r.acceptOwnership();
        assertEq(r.owner(), other);
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.NotOwner.selector);
        r.setStatus(t1, 1);
    }
}
