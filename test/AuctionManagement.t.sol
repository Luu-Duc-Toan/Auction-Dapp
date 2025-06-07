//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/AuctionManagement.sol";
import "../src/SampleProduct.sol";
import "../src/AuctionToken.sol";

contract AuctionTest is Test {
    AuctionManagement public auctionManagement;
    SampleProduct public product;

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
        product = new SampleProduct();
        product.mint(seller);
        vm.stopPrank();
    }

    function testAddValidProduct() public {
        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        assert(auctionManagement.addProduct(address(product), 0, 100) == true);

        AuctionManagement.Product[] memory addedProducts = auctionManagement.getPendingProducts();
        assert(addedProducts.length == 1);
        assert(addedProducts[0].productAddress == address(product));
        assert(addedProducts[0].productId == 0);
        assert(auctionManagement.getProductSeller(address(product), 0) == seller);
        vm.stopPrank();
    }

    function testAddInvalidProduct() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid product address");
        auctionManagement.addProduct(address(0), 1, 100);

        vm.expectRevert("Not the owner of the product");
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Product not approved");
        auctionManagement.addProduct(address(product), 0, 100);

        product.approve(address(auctionManagement), 0);
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("Auction is ongoing");
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();
    }

    function testRemoveProduct() public {
        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);

        assert(auctionManagement.removeProduct(address(product), 0) == true);
        AuctionManagement.Product[] memory pendingProducts = auctionManagement.getPendingProducts();
        assert(pendingProducts.length == 0);
        vm.stopPrank();
    }

    function testInvalidRemovingProduct() public {
        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        vm.expectRevert("Invalid product address");
        auctionManagement.removeProduct(address(0), 0);

        auctionManagement.addProduct(address(product), 0, 100);
        uint256 currentTime = block.timestamp;
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("Auction is ongoing");
        auctionManagement.removeProduct(address(product), 0);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.warp(currentTime);
        vm.expectRevert("Not the seller of the product");
        auctionManagement.removeProduct(address(product), 0);
        vm.stopPrank();
    }

    function testVerifyProduct() public {
        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        assert(auctionManagement.verifyProduct(0) == true);
        AuctionManagement.Product[] memory verifiedProducts = auctionManagement.getVerifiedProducts();
        assert(verifiedProducts.length == 1);
        assert(verifiedProducts[0].productAddress == address(product));
        assert(verifiedProducts[0].productId == 0);
        AuctionManagement.Product[] memory pendingProducts = auctionManagement.getPendingProducts();
        assert(pendingProducts.length == 0);
        vm.stopPrank();
    }

    function testInvalidVerifyingProduct() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid product index");
        auctionManagement.verifyProduct(0);
        vm.stopPrank();

        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", seller));
        auctionManagement.verifyProduct(0);
        vm.stopPrank();

        vm.startPrank(owner);
        assert(auctionManagement.verifyProduct(0) == true);
        vm.expectRevert("Invalid product index");
        auctionManagement.verifyProduct(1);

        vm.warp(auctionManagement.startTime() + auctionManagement.duration() - 1);
        vm.expectRevert("Auction is ongoing");
        auctionManagement.verifyProduct(0);
        vm.stopPrank();
    }

    function testBeginAndCloseAuction() public {
        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();
        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        assert(auctionManagement.lastBidTime() == block.timestamp);

        vm.warp(auctionManagement.startTime() + auctionManagement.duration());
        uint256 startTimeBeforeClose = auctionManagement.startTime();
        assert(auctionManagement.closeAuction() == true);
        assert(auctionManagement.lastBidTime() == 0);
        assert(auctionManagement.startTime() == startTimeBeforeClose + auctionManagement.elapsedTime());
        assert(auctionManagement.currentProductIndex() == 0);
        AuctionManagement.Product[] memory productsAfterClose = auctionManagement.getVerifiedProducts();
        assert(productsAfterClose.length == 0);
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
        vm.expectRevert("No products available for bidding");
        auctionManagement.beginAuction();

        vm.expectRevert("Auction is ongoing");
        auctionManagement.closeAuction();

        vm.warp(auctionManagement.startTime() - 1);
        vm.expectRevert("Auction has not started yet");
        auctionManagement.closeAuction();
        vm.stopPrank();

        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);

        vm.stopPrank();
        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.expectRevert("Auction has already started");
        auctionManagement.beginAuction();
        vm.stopPrank();
    }

    function testBid() public {
        vm.startPrank(seller);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);
        uint256 bidAmount = 100;
        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        assert(auctionManagement.bid(bidAmount) == true);
        assert(auctionManagement.getProductPrice(address(product), 0) == bidAmount);
        assert(auctionManagement.getProductOwner(address(product), 0) == bidder1);
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
        vm.expectRevert("No products available for bidding");
        auctionManagement.bid(bidAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
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
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.stopPrank();

        vm.startPrank(bidder1);
        uint256 bidAmount = 100;
        AuctionToken(auctionManagement.auctionTokenAddress()).approve(address(auctionManagement), bidAmount);
        auctionManagement.bid(bidAmount);

        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        assert(auctionManagement.gavel() == true);
        assert(auctionManagement.currentProductIndex() == 1);
        assert(auctionManagement.lastBidTime() == block.timestamp);
        address expectedOwner = auctionManagement.getProductOwner(address(product), 0);
        assert(expectedOwner == bidder1);
        assert(auctionManagement.getProductPrice(address(product), 0) == bidAmount);
        assert(auctionManagement.getProductSeller(address(product), 0) == seller);
        vm.warp(auctionManagement.startTime() + auctionManagement.duration() + 1);
        auctionManagement.closeAuction();
        vm.stopPrank();

        //unsold gavel
        vm.startPrank(owner);
        product.mint(seller);
        vm.stopPrank();
        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        product.approve(address(auctionManagement), 1);
        auctionManagement.addProduct(address(product), 1, 100);
        vm.stopPrank();
        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
        vm.warp(auctionManagement.startTime() + 1);
        auctionManagement.beginAuction();
        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        assert(auctionManagement.gavel() == true);
        assert(auctionManagement.lastBidTime() == block.timestamp);
        expectedOwner = auctionManagement.getProductOwner(address(product), 1);
        assert(expectedOwner == address(0));
        assert(auctionManagement.getProductPrice(address(product), 1) == 0);
        assert(auctionManagement.getProductSeller(address(product), 1) == seller);
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
        vm.expectRevert("No products available for bidding");
        auctionManagement.gavel();
        vm.stopPrank();

        vm.startPrank(seller);
        vm.warp(auctionManagement.startTime() - 1);
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
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
        product.approve(address(auctionManagement), 0);
        auctionManagement.addProduct(address(product), 0, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
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

        assert(auctionManagement.bidderClaim(address(product), 0) == true);
        address expectedOwner = auctionManagement.getProductOwner(address(product), 0);
        assert(expectedOwner == address(0));
        assert(ERC721(product).ownerOf(0) == bidder1);

        //seller claim sold product
        vm.startPrank(seller);
        uint256 sellerBalanceBefore = AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller);
        assert(auctionManagement.sellerClaim(address(product), 0) == true);
        address expectedSeller = auctionManagement.getProductSeller(address(product), 0);
        assert(expectedSeller == address(0));
        assert(
            AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller) == sellerBalanceBefore + bidAmount
        );

        //seller claim unsold product
        vm.startPrank(owner);
        product.mint(seller);
        vm.stopPrank();

        vm.startPrank(seller);
        product.approve(address(auctionManagement), 1);
        auctionManagement.addProduct(address(product), 1, 100);
        vm.stopPrank();

        vm.startPrank(owner);
        auctionManagement.verifyProduct(0);
        vm.warp(auctionManagement.startTime());
        auctionManagement.beginAuction();
        vm.warp(block.timestamp + auctionManagement.fairWarningTime());
        auctionManagement.gavel();
        vm.warp(auctionManagement.startTime() + auctionManagement.duration());
        auctionManagement.closeAuction();
        vm.stopPrank();

        vm.startPrank(seller);
        sellerBalanceBefore = AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller);
        assert(auctionManagement.sellerClaim(address(product), 1) == true);
        expectedSeller = auctionManagement.getProductSeller(address(product), 1);
        assert(expectedSeller == address(0));
        assert(ERC721(product).ownerOf(1) == seller);
        assert(AuctionToken(auctionManagement.auctionTokenAddress()).balanceOf(seller) == sellerBalanceBefore);
        vm.stopPrank();
    }
}
