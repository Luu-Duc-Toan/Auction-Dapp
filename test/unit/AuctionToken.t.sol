// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/AuctionToken.sol";

contract AuctionTokenTest is Test {
    AuctionToken public auctionToken;
    address public owner;
    address public user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.startPrank(owner);
        auctionToken = new AuctionToken();
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(auctionToken.name(), "AuctionToken");
        assertEq(auctionToken.symbol(), "ATK");
        assertEq(auctionToken.owner(), owner);
        assertEq(auctionToken.totalSupply(), 0);
    }

    function testMintAsOwner() public {
        vm.startPrank(owner);
        auctionToken.mint(user, 100);
        vm.stopPrank();

        assertEq(auctionToken.balanceOf(user), 100);
        assertEq(auctionToken.totalSupply(), 100);
    }

    function testMintAsNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        auctionToken.mint(user, 100);
        vm.stopPrank();
    }

    function testTransfer() public {
        address recipient = makeAddr("recipient");

        // First mint some tokens
        vm.prank(owner);
        auctionToken.mint(user, 100);

        // Then transfer them
        vm.prank(user);
        auctionToken.transfer(recipient, 50);

        assertEq(auctionToken.balanceOf(user), 50);
        assertEq(auctionToken.balanceOf(recipient), 50);
    }

    function testApproveAndTransferFrom() public {
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");

        // First mint some tokens
        vm.prank(owner);
        auctionToken.mint(user, 100);

        // Then approve spending
        vm.prank(user);
        auctionToken.approve(spender, 70);

        // Then transfer from approved amount
        vm.prank(spender);
        auctionToken.transferFrom(user, recipient, 50);

        assertEq(auctionToken.balanceOf(user), 50);
        assertEq(auctionToken.balanceOf(recipient), 50);
        assertEq(auctionToken.allowance(user, spender), 20);
    }

    function testOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(owner);
        auctionToken.transferOwnership(newOwner);
        vm.stopPrank();

        assertEq(auctionToken.owner(), newOwner);

        // Test that old owner can't mint anymore
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        auctionToken.mint(user, 100);
        vm.stopPrank();

        // Test that new owner can mint
        vm.startPrank(newOwner);
        auctionToken.mint(user, 100);
        vm.stopPrank();

        assertEq(auctionToken.balanceOf(user), 100);
    }
}
