// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/AuctionManagement.sol";
import "../../src/AuctionToken.sol";
import "../../src/SampleAsset.sol";

contract AuctionManagementTest is Test {
    AuctionManagement public auctionManagement;
    AuctionToken public auctionToken;
    SampleAsset public sampleAsset;

    address public owner;
    address public seller;
    address public bidder1;
    address public bidder2;

    uint256 public startTime;
    uint256 public duration;
    uint256 public elapsedTime;
    uint256 public fairWarningTime;

    function setUp() public {
        owner = makeAddr("owner");
        seller = makeAddr("seller");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");

        startTime = block.timestamp + 100; // Start in the future
        duration = 3600; // 1 hour
        elapsedTime = 86400; // 1 day
        fairWarningTime = 300; // 5 minutes

        vm.startPrank(owner);
        auctionManagement = new AuctionManagement(startTime, duration, elapsedTime, fairWarningTime);

        // Get the auction token address
        address tokenAddress = auctionManagement.auctionTokenAddress();
        auctionToken = AuctionToken(tokenAddress);

        // Mint tokens for bidders
        auctionToken.mint(bidder1, 1000);
        auctionToken.mint(bidder2, 2000);

        // Create sample asset for testing
        sampleAsset = new SampleAsset();
        vm.stopPrank();

        // Mint assets to seller
        vm.startPrank(owner);
        sampleAsset.mint(seller);
        sampleAsset.mint(seller);
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(auctionManagement.startTime(), startTime);
        assertEq(auctionManagement.duration(), duration);
        assertEq(auctionManagement.elapsedTime(), elapsedTime);
        assertEq(auctionManagement.fairWarningTime(), fairWarningTime);
        assertEq(auctionManagement.currentAssetIndex(), 0);
        assertEq(auctionManagement.lastBidTime(), 0);
    }

    function testAddAsset() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // Approve asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), tokenId);
        bool success = auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();

        assertTrue(success);
        assertEq(sampleAsset.ownerOf(tokenId), address(auctionManagement));
        assertEq(auctionManagement.getAssetSeller(address(sampleAsset), tokenId), seller);
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), tokenId), minPrice - 1);
    }

    function testAddAssetFailsWhenNotOwner() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        vm.startPrank(bidder1);
        vm.expectRevert("Not the owner of the asset");
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();
    }

    function testAddAssetFailsWhenNotApproved() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // Don't approve, should fail
        vm.startPrank(seller);
        vm.expectRevert("Asset not approved");
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();
    }

    function testRemoveAsset() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // Add asset first
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), tokenId);
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);

        // Then remove it
        bool success = auctionManagement.removeAsset(address(sampleAsset), tokenId);
        vm.stopPrank();

        assertTrue(success);
        assertEq(sampleAsset.ownerOf(tokenId), seller);
        // Check that asset data is removed
        assertEq(auctionManagement.getAssetSeller(address(sampleAsset), tokenId), address(0));
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), tokenId), 0);
    }

    function testVerifyAsset() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // Add asset first
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), tokenId);
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();

        // Owner verifies the asset
        vm.startPrank(owner);
        bool success = auctionManagement.verifyAsset(0);
        vm.stopPrank();

        assertTrue(success);
    }

    function testAuctionWorkflow() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // 1. Add and verify asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), tokenId);
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        // 2. Start the auction
        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // 3. Bidder1 places bid
        vm.startPrank(bidder1);
        auctionToken.approve(address(auctionManagement), 150);
        auctionManagement.bid(150);
        vm.stopPrank();

        // Verify bid
        assertEq(auctionToken.balanceOf(bidder1), 850);
        assertEq(auctionManagement.getAssetOwner(address(sampleAsset), tokenId), bidder1);
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), tokenId), 150);

        // 4. Bidder2 places higher bid
        vm.startPrank(bidder2);
        auctionToken.approve(address(auctionManagement), 200);
        auctionManagement.bid(200);
        vm.stopPrank();

        // Verify new bid
        assertEq(auctionToken.balanceOf(bidder1), 1000);
        assertEq(auctionToken.balanceOf(bidder2), 1800);
        assertEq(auctionManagement.getAssetOwner(address(sampleAsset), tokenId), bidder2);
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), tokenId), 200);

        // 5. End the auction with gavel after fair warning time
        vm.warp(block.timestamp + fairWarningTime + 1);
        vm.prank(owner);
        auctionManagement.gavel();

        // 6. End the auction
        vm.warp(startTime + duration + 1);
        vm.prank(owner);
        auctionManagement.closeAuction();

        // 7. Bidder claims the asset
        vm.prank(bidder2);
        auctionManagement.bidderClaim(address(sampleAsset), tokenId);
        assertEq(sampleAsset.ownerOf(tokenId), bidder2);

        // 8. Seller claims the payment
        vm.prank(seller);
        auctionManagement.sellerClaim(address(sampleAsset), tokenId);
        assertEq(auctionToken.balanceOf(seller), 200);
    }

    function testGavelWithNoBids() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // Setup auction
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), tokenId);
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // No bids placed, gavel after fair warning time
        vm.warp(block.timestamp + fairWarningTime + 1);
        vm.prank(owner);
        auctionManagement.gavel();

        // Asset should have price set to 0 since there were no bids
        assertEq(auctionManagement.getAssetPrice(address(sampleAsset), tokenId), 0);
    }

    function testSellerClaimUnbidAsset() public {
        uint256 tokenId = 0;
        uint256 minPrice = 100;

        // Setup auction
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), tokenId);
        auctionManagement.addAsset(address(sampleAsset), tokenId, minPrice);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // No bids placed, gavel after fair warning time
        vm.warp(block.timestamp + fairWarningTime + 1);
        vm.prank(owner);
        auctionManagement.gavel();

        // End auction
        vm.warp(startTime + duration + 1);
        vm.prank(owner);
        auctionManagement.closeAuction();

        // Seller claims the unsold asset back
        vm.prank(seller);
        auctionManagement.sellerClaim(address(sampleAsset), tokenId);

        // Seller should get the asset back
        assertEq(sampleAsset.ownerOf(tokenId), seller);
    }
}
