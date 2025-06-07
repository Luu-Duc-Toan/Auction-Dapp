// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./AuctionToken.sol";
import "forge-std/console.sol";

//How to check whether the product is a ERC721 token? (valid product)
//add lending function
contract AuctionManagement is Ownable {
    struct Product {
        address productAddress;
        uint256 productId;
    }

    address public auctionTokenAddress;
    uint256 public startTime;
    uint256 public duration;
    uint256 public elapsedTime;
    uint256 public currentProductIndex;
    uint256 public fairWarningTime;
    uint256 public lastBidTime;
    Product[] pendingProducts;
    Product[] verifiedProducts;
    mapping(bytes32 => address) productOwners;
    mapping(bytes32 => address) productSellers;
    mapping(bytes32 => uint256) prices;

    constructor(uint256 _startTime, uint256 _duration, uint256 _elapsedTime, uint256 _fairWarningTime)
        Ownable(msg.sender)
    {
        startTime = _startTime;
        duration = _duration;
        elapsedTime = _elapsedTime;
        fairWarningTime = _fairWarningTime;
        auctionTokenAddress = address(new AuctionToken());
        AuctionToken(auctionTokenAddress).transferOwnership(msg.sender);
    }

    modifier inAuction() {
        require(block.timestamp >= startTime, "Auction has not started yet");
        require(block.timestamp < startTime + duration, "Auction has already ended");
        require(currentProductIndex < verifiedProducts.length, "No products available for bidding");
        _;
    }

    modifier notInAuction() {
        require(block.timestamp < startTime || block.timestamp >= startTime + duration, "Auction is ongoing");
        _;
    }

    modifier validProduct(address product) {
        require(product != address(0), "Invalid product address");
        _;
    }

    function getProductHash(address productAddress, uint256 productId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(productAddress, productId));
    }

    function addProduct(address product, uint256 id, uint256 minPrice)
        external
        notInAuction
        validProduct(product)
        returns (bool)
    {
        require(ERC721(product).ownerOf(id) == msg.sender, "Not the owner of the product");
        require(ERC721(product).getApproved(id) == address(this), "Product not approved");
        ERC721(product).transferFrom(msg.sender, address(this), id);
        Product memory newProduct = Product({productAddress: product, productId: id});
        pendingProducts.push(newProduct);
        bytes32 productHash = getProductHash(product, id);
        productSellers[productHash] = msg.sender;
        prices[productHash] = minPrice - 1;
        return true;
    }

    function removeProduct(address product, uint256 id) external notInAuction validProduct(product) returns (bool) {
        bytes32 productHash = getProductHash(product, id);
        require(productSellers[productHash] == msg.sender, "Not the seller of the product");
        for (uint256 i = 0; i < pendingProducts.length; ++i) {
            if (pendingProducts[i].productAddress != product || pendingProducts[i].productId != id) continue;
            pendingProducts[i] = pendingProducts[pendingProducts.length - 1];
            pendingProducts.pop();
            delete productSellers[productHash];
            delete prices[productHash];
            return true;
        }
        for (uint256 i = 0; i < verifiedProducts.length; ++i) {
            if (verifiedProducts[i].productAddress != product || verifiedProducts[i].productId != id) continue;
            verifiedProducts[i] = verifiedProducts[verifiedProducts.length - 1];
            verifiedProducts.pop();
            delete productSellers[productHash];
            delete prices[productHash];
            return true;
        }
        return false; //dont find the product (in which case?)
    }

    function getPendingProducts() external view notInAuction returns (Product[] memory) {
        return pendingProducts;
    }

    function verifyProduct(uint256 index) external notInAuction onlyOwner returns (bool) {
        require(index < pendingProducts.length, "Invalid product index");
        verifiedProducts.push(pendingProducts[index]);
        pendingProducts[index] = pendingProducts[pendingProducts.length - 1];
        pendingProducts.pop();
        return true;
    }

    function getVerifiedProducts() external view notInAuction returns (Product[] memory) {
        return verifiedProducts;
    }

    function getProductPrice(address product, uint256 id) external view validProduct(product) returns (uint256) {
        console.log("getProductPrice", product, id);
        return prices[getProductHash(product, id)];
    }

    function getProductOwner(address product, uint256 id) external view validProduct(product) returns (address) {
        console.log("getProductOwner", product, id);
        return productOwners[getProductHash(product, id)];
    }

    function getProductSeller(address product, uint256 id) external view validProduct(product) returns (address) {
        return productSellers[getProductHash(product, id)];
    }

    function beginAuction() external inAuction returns (bool) {
        require(lastBidTime < startTime, "Auction has already started");
        lastBidTime = block.timestamp;
        return true;
    }

    function closeAuction() external notInAuction returns (bool) {
        require(lastBidTime >= startTime, "Auction has not started yet");
        currentProductIndex = 0;
        lastBidTime = 0;
        startTime += elapsedTime;
        delete verifiedProducts;
        return true;
    }

    function bid(uint256 amount) external inAuction returns (bool) {
        bytes32 productHash = getProductHash(
            verifiedProducts[currentProductIndex].productAddress, verifiedProducts[currentProductIndex].productId
        );
        require(amount > prices[productHash], "Bid amount must be greater than the current price");
        require(AuctionToken(auctionTokenAddress).balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(AuctionToken(auctionTokenAddress).allowance(msg.sender, address(this)) >= amount, "Allowance too low");
        AuctionToken(auctionTokenAddress).transferFrom(msg.sender, address(this), amount);
        prices[productHash] = amount;
        productOwners[productHash] = msg.sender;
        lastBidTime = block.timestamp;
        return true;
    }

    function gavel() external inAuction returns (bool) {
        require(block.timestamp - lastBidTime >= fairWarningTime, "Fair warning time has not elapsed since last bid");
        require(currentProductIndex < verifiedProducts.length, "No products available for gaveling");
        bytes32 productHash = getProductHash(
            verifiedProducts[currentProductIndex].productAddress, verifiedProducts[currentProductIndex].productId
        );
        if (productOwners[productHash] == address(0)) {
            prices[productHash] = 0;
        }
        currentProductIndex++;
        lastBidTime = block.timestamp;
        return true;
    }

    function bidderClaim(address product, uint256 id) external notInAuction validProduct(product) returns (bool) {
        bytes32 productHash = getProductHash(product, id);
        require(productOwners[productHash] == msg.sender, "Not the owner of the product");
        ERC721(product).safeTransferFrom(address(this), msg.sender, id);
        delete productOwners[productHash];
        return true;
    }

    function sellerClaim(address product, uint256 id) external notInAuction validProduct(product) returns (bool) {
        bytes32 productHash = getProductHash(product, id);
        require(productSellers[productHash] == msg.sender, "Not the owner of the product");
        if (prices[productHash] != 0) {
            AuctionToken(auctionTokenAddress).transfer(msg.sender, prices[productHash]);
        } else {
            ERC721(product).safeTransferFrom(address(this), msg.sender, id);
        }
        delete productSellers[productHash];
        delete prices[productHash];
        return true;
    }

    function getCurrentProduct() external view inAuction returns (Product memory) {
        return verifiedProducts[currentProductIndex];
    }
}
