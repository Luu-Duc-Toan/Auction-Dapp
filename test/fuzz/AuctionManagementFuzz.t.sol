// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/AuctionManagement.sol";
import "../../src/AuctionToken.sol";
import "../../src/SampleAsset.sol";

contract AuctionManagementFuzzTest is Test {
    AuctionManagement public auctionManagement;
    AuctionToken public auctionToken;
    SampleAsset public sampleAsset;

    address public owner;
    address public seller;
    address public bidder;

    function setUp() public {
        owner = makeAddr("owner");
        seller = makeAddr("seller");
        bidder = makeAddr("bidder");

        vm.startPrank(owner);
        auctionManagement = new AuctionManagement(block.timestamp + 100, 3600, 86400, 300);

        // Get auction token
        address tokenAddr = auctionManagement.auctionTokenAddress();
        auctionToken = AuctionToken(tokenAddr);

        // Create sample asset
        sampleAsset = new SampleAsset();

        // Mint asset to seller
        sampleAsset.mint(seller);

        // Mint tokens to bidder
        auctionToken.mint(bidder, 1000000); // Large amount for fuzz tests
        vm.stopPrank();

        // Seller approves asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 100);
        vm.stopPrank();

        // Owner verifies asset
        vm.prank(owner);
        auctionManagement.verifyAsset(0);
    }

    function testFuzzBidding(uint256 bidAmount) public {
        // Bound the bid amount between 100 and 1000000
        bidAmount = bound(bidAmount, 100, 1000000);

        // Start auction
        vm.warp(block.timestamp + 100);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // Bidder places bid
        vm.startPrank(bidder);
        auctionToken.approve(address(auctionManagement), bidAmount);

        // Only bid if higher than current price
        uint256 currentPrice = auctionManagement.getAssetPrice(address(sampleAsset), 0);
        vm.assume(bidAmount > currentPrice);

        auctionManagement.bid(bidAmount);
        vm.stopPrank();

        // Verify bid was placed
        assertEq(auctionManagement.getAssetOwner(address(sampleAsset), 0), bidder);
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), 0), bidAmount);
    }

    function testFuzzMultipleBids(uint256 firstBid, uint256 secondBid) public {
        // Bound the bid amounts
        firstBid = bound(firstBid, 100, 500000);
        secondBid = bound(secondBid, firstBid + 1, 1000000);

        address bidder2 = makeAddr("bidder2");

        // Give tokens to second bidder
        vm.prank(owner);
        auctionToken.mint(bidder2, 1000000);

        // Start auction
        vm.warp(block.timestamp + 100);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // First bidder bids
        vm.startPrank(bidder);
        auctionToken.approve(address(auctionManagement), firstBid);
        auctionManagement.bid(firstBid);
        vm.stopPrank();

        // Second bidder bids higher
        vm.startPrank(bidder2);
        auctionToken.approve(address(auctionManagement), secondBid);
        auctionManagement.bid(secondBid);
        vm.stopPrank();

        // Verify second bid was placed
        assertEq(auctionManagement.getAssetOwner(address(sampleAsset), 0), bidder2);
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), 0), secondBid);
    }

    function testFuzzGavelTiming(uint256 timeElapsed) public {
        // Bound time elapsed between fair warning time and a reasonable upper limit
        timeElapsed = bound(timeElapsed, 0, auctionManagement.fairWarningTime());

        // Start auction
        vm.warp(block.timestamp + 100);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // Bidder places bid
        vm.startPrank(bidder);
        auctionToken.approve(address(auctionManagement), 200);
        auctionManagement.bid(200);
        vm.stopPrank();

        // Fast forward by the fuzzed time
        vm.warp(block.timestamp + timeElapsed);

        // Try to gavel
        vm.prank(owner);

        // Should succeed if time elapsed >= fair warning time
        if (timeElapsed >= auctionManagement.fairWarningTime()) {
            auctionManagement.gavel();
            // Check that we moved to the next asset
            assertEq(auctionManagement.currentAssetIndex(), 1);
        } else {
            vm.expectRevert("Fair warning time has not elapsed since last bid");
            auctionManagement.gavel();
        }
    }
}
