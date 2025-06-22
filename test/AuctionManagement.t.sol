//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/AuctionManagement.sol";
import "../src/SampleAsset.sol";
import "../src/AuctionToken.sol";

contract AuctionTest is Test {
    AuctionManagement public auctionManagement;
    SampleAsset public asset;

    address public owner;
    address public seller;
    address public bidder1;
    address public bidder2;

    function setUp() public {
        owner = address(this);
        seller = address(0x1);
        bidder1 = address(0x2);
        bidder2 = address(0x3);
        vm.startPrank(owner);
        auctionManagement = new AuctionManagement(block.timestamp + 1 days, 1 hours, 1 days, 1 minutes);
        AuctionToken(auctionManagement.auctionTokenAddress()).mint(owner, 1000000);
        console.log("Balance of owner:", AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(owner));
        AuctionToken(auctionManagement.auctionTokenAddress()).transfer(bidder1, 10000);
        AuctionToken(auctionManagement.auctionTokenAddress()).transfer(bidder2, 10000);
        vm.stopPrank();
        asset = new SampleAsset();
        asset.mint(seller);
        vm.stopPrank();
    }

    function testAddValidAsset() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        assert(auctionManagement.addAsset(address(asset), 0, 100) == true);

        AuctionManagement.Asset[] memory addedAssets = auctionManagement.getPendingAssets();
        assert(addedAssets.length == 1);
        assert(addedAssets[0].assetAddress == address(asset));
        assert(addedAssets[0].assetId == 0);
        assert(auctionManagement.getAssetSeller(address(asset), 0) == seller);
        vm.stopPrank();
    }

    function testAddInvalidAsset() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid asset address");
        auctionManagement.addAsset(address(0), 1, 100);

        vm.expectRevert("Not the owner of the asset");
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Asset not approved");
        auctionManagement.addAsset(address(asset), 0, 100);

        asset.approve(address(auctionManagement), 0);
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("Auction is ongoing");
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();
    }

    function testRemoveAsset() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);

        assert(auctionManagement.removeAsset(address(asset), 0) == true);
        AuctionManagement.Asset[] memory pendingAssets = auctionManagement.getPendingAssets();
        assert(pendingAssets.length == 0);
        vm.stopPrank();
    }

    function testInvalidRemovingAsset() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        vm.expectRevert("Invalid asset address");
        auctionManagement.removeAsset(address(0), 0);

        auctionManagement.addAsset(address(asset), 0, 100);
        uint256 currentTime = block.timestamp;
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("Auction is ongoing");
        auctionManagement.removeAsset(address(asset), 0);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.warp(currentTime);
        vm.expectRevert("Not the seller of the asset");
        auctionManagement.removeAsset(address(asset), 0);
        vm.stopPrank();
    }

    function testVerifyAsset() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        assert(auctionManagement.verifyAsset(0) == true);
        AuctionManagement.Asset[] memory verifiedAssets = auctionManagement.getVerifiedAssets();
        assert(verifiedAssets.length == 1);
        assert(verifiedAssets[0].assetAddress == address(asset));
        assert(verifiedAssets[0].assetId == 0);
        AuctionManagement.Asset[] memory pendingAssets = auctionManagement.getPendingAssets();
        assert(pendingAssets.length == 0);
        vm.stopPrank();
    }

    function testInvalidVerifyingAsset() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid asset index");
        auctionManagement.verifyAsset(0);
        vm.stopPrank();

        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", seller));
        auctionManagement.verifyAsset(0);
        vm.stopPrank();

        vm.startPrank(owner);
        assert(auctionManagement.verifyAsset(0) == true);
        vm.expectRevert("Invalid asset index");
        auctionManagement.verifyAsset(1);

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("Auction is ongoing");
        auctionManagement.verifyAsset(0);
        vm.stopPrank();
    }

    function testBeginAndCloseAuction() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();
        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        assert(auctionManagement.lastBidTime() == block.timestamp);

        vm.warp(auctionManagement.startTime() + auctionManagement.duration());
        uint256 startTimeBeforeClose = auctionManagement.startTime();
        assert(auctionManagement.closeAuction() == true);
        assert(auctionManagement.lastBidTime() == 0);
        assert(auctionManagement.startTime() == startTimeBeforeClose + auctionManagement.elapsedTime());
        assert(auctionManagement.currentAssetIndex() == 0);
        AuctionManagement.Asset[] memory AssetsAfterClose = auctionManagement.getVerifiedAssets();
        assert(AssetsAfterClose.length == 0);
        vm.stopPrank();
    }

    function testInvalidBeginningAuction() public {
        vm.startPrank(owner);
        vm.expectRevert("Auction has not started yet");
        auctionManagement.beginAuction();

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() + 1);
        vm.expectRevert("Auction has already ended");
        auctionManagement.beginAuction();

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("No asset available for bidding");
        auctionManagement.beginAuction();

        vm.expectRevert("Auction is ongoing");
        auctionManagement.closeAuction();

        vm.warp(auctionManagement.startTime() - 1);
        vm.expectRevert("Auction has not started yet");
        auctionManagement.closeAuction();
        vm.stopPrank();

        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);

        vm.stopPrank();
        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.expectRevert("Auction has already started");
        auctionManagement.beginAuction();
        vm.stopPrank();
    }

    function testBid() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);
        uint256 bidAmount = 100;
        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        assert(auctionManagement.bid(bidAmount) == true);
        assert(auctionManagement.getAssetPrice(address(asset), 0) == bidAmount);
        assert(auctionManagement.getAssetOwner(address(asset), 0) == bidder1);
        assert(auctionManagement.lastBidTime() == block.timestamp);
        vm.stopPrank();
    }

    function testInvalidBidding() public {
        uint256 bidAmount = 100;
        uint256 insufficientBalance = AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(bidder1) + 1;

        vm.startPrank(bidder1);
        vm.warp(auctionManagement.startTime() - 1);
        vm.expectRevert("Auction has not started yet");
        auctionManagement.bid(bidAmount);

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() + 1);
        vm.expectRevert("Auction has already ended");
        auctionManagement.bid(bidAmount);

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("No asset available for bidding");
        auctionManagement.bid(bidAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);

        vm.expectRevert("Allowance too low");
        auctionManagement.bid(bidAmount);

        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        vm.expectRevert("Bid amount must be greater than the current price");
        auctionManagement.bid(bidAmount - 1);

        vm.expectRevert("Insufficient balance");
        auctionManagement.bid(insufficientBalance);

        vm.stopPrank();
    }

    function testGavel() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);
        uint256 bidAmount = 100;
        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        auctionManagement.bid(bidAmount);

        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        assert(auctionManagement.gavel() == true);
        assert(auctionManagement.currentAssetIndex() == 1);
        assert(auctionManagement.lastBidTime() == block.timestamp);
        address expectedOwner = auctionManagement.getAssetOwner(address(asset), 0);
        assert(expectedOwner == bidder1);
        assert(auctionManagement.getAssetPrice(address(asset), 0) == bidAmount);
        assert(auctionManagement.getAssetSeller(address(asset), 0) == seller);
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() + 1);
        auctionManagement.closeAuction();
        vm.stopPrank();

        //unsold gavel
        vm.startPrank(owner);
        asset.mint(seller);
        vm.stopPrank();
        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        asset.approve(address(auctionManagement), 1);
        auctionManagement.addAsset(address(asset), 1, 100);
        vm.stopPrank();
        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime() + 1);
        auctionManagement.beginAuction();
        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        assert(auctionManagement.gavel() == true);
        assert(auctionManagement.lastBidTime() == block.timestamp);
        expectedOwner = auctionManagement.getAssetOwner(address(asset), 1);
        assert(expectedOwner == address(0));
        assert(auctionManagement.getAssetPrice(address(asset), 1) == 0);
        assert(auctionManagement.getAssetSeller(address(asset), 1) == seller);
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() + 1);
        auctionManagement.closeAuction();
        vm.stopPrank();
    }

    function testInvalidGavel() public {
        vm.startPrank(owner);
        vm.expectRevert("Auction has not started yet");
        auctionManagement.gavel();

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() + 1);
        vm.expectRevert("Auction has already ended");
        auctionManagement.gavel();

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("No asset available for bidding");
        auctionManagement.gavel();
        vm.stopPrank();

        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);
        uint256 bidAmount = 100;
        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        auctionManagement.bid(bidAmount);

        vm.expectRevert("Fair warning time has not elapsed since last bid");
        auctionManagement.gavel();

        vm.stopPrank();
    }

    function testClaiming() public {
        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(asset), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);
        uint256 bidAmount = 100;
        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        auctionManagement.bid(bidAmount);

        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        auctionManagement.gavel();
        vm.warp(auctionManagement.startTime() + auctionManagement.duration());
        auctionManagement.closeAuction();

        assert(auctionManagement.bidderClaim(address(asset), 0) == true);
        address expectedOwner = auctionManagement.getAssetOwner(address(asset), 0);
        assert(expectedOwner == address(0));
        assert(ERC721(asset).ownerOf(0) == bidder1);

        //seller claim sold Asset
        vm.startPrank(seller);
        uint256 sellerBalanceBefore = AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller);
        assert(auctionManagement.sellerClaim(address(asset), 0) == true);
        address expectedSeller = auctionManagement.getAssetSeller(address(asset), 0);
        assert(expectedSeller == address(0));
        assert(
            AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller) == sellerBalanceBefore + bidAmount
        );

        //seller claim unsold Asset
        vm.startPrank(owner);
        asset.mint(seller);
        vm.stopPrank();

        vm.startPrank(seller);
        asset.approve(address(auctionManagement), 1);
        auctionManagement.addAsset(address(asset), 1, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        auctionManagement.gavel();
        vm.warp(auctionManagement.startTime() + auctionManagement.duration());
        auctionManagement.closeAuction();
        vm.stopPrank();

        vm.startPrank(seller);
        sellerBalanceBefore = AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller);
        assert(auctionManagement.sellerClaim(address(asset), 1) == true);
        expectedSeller = auctionManagement.getAssetSeller(address(asset), 1);
        assert(expectedSeller == address(0));
        assert(ERC721(asset).ownerOf(1) == seller);
        assert(AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller) == sellerBalanceBefore);
        vm.stopPrank();
    }
}
