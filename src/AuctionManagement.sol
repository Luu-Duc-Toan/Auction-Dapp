// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./AuctionToken.sol";
import "forge-std/console.sol";

//How to check whether the product is a ERC721 token? (valid product)
//add lending function
contract AuctionManagement is Ownable {
    struct Asset {
        address assetAddress;
        uint256 assetId;
    }

    address public auctionTokenAddress;
    uint256 public startTime;
    uint256 public duration;
    uint256 public elapsedTime;
    uint256 public currentAssetIndex;
    uint256 public fairWarningTime;
    uint256 public lastBidTime;
    Asset[] pendingAssets;
    Asset[] verifiedAssets;
    mapping(bytes32 => address) owners;
    mapping(bytes32 => address) sellers;
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
        require(currentAssetIndex < verifiedAssets.length, "No asset available for bidding");
        _;
    }

    modifier notInAuction() {
        require(block.timestamp < startTime || block.timestamp >= startTime + duration, "Auction is ongoing");
        _;
    }

    modifier validAsset(address asset) {
        require(asset != address(0), "Invalid asset address");
        _;
    }

    function getAssetHash(address assetAddress, uint256 assetId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(assetAddress, assetId));
    }

    function addAsset(address asset, uint256 id, uint256 minPrice)
        external
        notInAuction
        validAsset(asset)
        returns (bool)
    {
        require(ERC721(asset).ownerOf(id) == msg.sender, "Not the owner of the asset");
        require(ERC721(asset).getApproved(id) == address(this), "Asset not approved");
        ERC721(asset).transferFrom(msg.sender, address(this), id);
        Asset memory newAsset = Asset({assetAddress: asset, assetId: id});
        pendingAssets.push(newAsset);
        bytes32 assetHash = getAssetHash(asset, id);
        sellers[assetHash] = msg.sender;
        prices[assetHash] = minPrice - 1;
        return true;
    }

    function removeAsset(address asset, uint256 id) external notInAuction validAsset(asset) returns (bool) {
        bytes32 assetHash = getAssetHash(asset, id);
        require(sellers[assetHash] == msg.sender, "Not the seller of the asset");
        for (uint256 i = 0; i < pendingAssets.length; ++i) {
            if (pendingAssets[i].assetAddress != asset || pendingAssets[i].assetId != id) continue;
            pendingAssets[i] = pendingAssets[pendingAssets.length - 1];
            pendingAssets.pop();
            delete sellers[assetHash];
            delete prices[assetHash];
            return true;
        }
        for (uint256 i = 0; i < verifiedAssets.length; ++i) {
            if (verifiedAssets[i].assetAddress != asset || verifiedAssets[i].assetId != id) continue;
            verifiedAssets[i] = verifiedAssets[verifiedAssets.length - 1];
            verifiedAssets.pop();
            delete sellers[assetHash];
            delete prices[assetHash];
            return true;
        }
        return false; //dont find the asset (in which case?)
    }

    function verifyAsset(uint256 index) external notInAuction onlyOwner returns (bool) {
        require(index < pendingAssets.length, "Invalid asset index");
        verifiedAssets.push(pendingAssets[index]);
        pendingAssets[index] = pendingAssets[pendingAssets.length - 1];
        pendingAssets.pop();
        return true;
    }

    function beginAuction() external inAuction returns (bool) {
        require(lastBidTime < startTime, "Auction has already started");
        lastBidTime = block.timestamp;
        return true;
    }

    function closeAuction() external notInAuction returns (bool) {
        require(lastBidTime >= startTime, "Auction has not started yet");
        currentAssetIndex = 0;
        lastBidTime = 0;
        startTime += elapsedTime;
        delete pendingAssets;
        delete verifiedAssets;
        return true;
    }

    function bid(uint256 amount) external inAuction returns (bool) {
        bytes32 assetHash =
            getAssetHash(verifiedAssets[currentAssetIndex].assetAddress, verifiedAssets[currentAssetIndex].assetId);
        require(amount > prices[assetHash], "Bid amount must be greater than the current price");
        require(AuctionToken(auctionTokenAddress).balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(AuctionToken(auctionTokenAddress).allowance(msg.sender, address(this)) >= amount, "Allowance too low");
        AuctionToken(auctionTokenAddress).transferFrom(msg.sender, address(this), amount);
        if (owners[assetHash] != address(0)) {
            AuctionToken(auctionTokenAddress).transfer(owners[assetHash], prices[assetHash]);
        }
        prices[assetHash] = amount;
        owners[assetHash] = msg.sender;
        lastBidTime = block.timestamp;
        return true;
    }

    function gavel() external inAuction returns (bool) {
        require(block.timestamp - lastBidTime >= fairWarningTime, "Fair warning time has not elapsed since last bid");
        require(currentAssetIndex < verifiedAssets.length, "No asset available for gaveling");
        bytes32 assetHash =
            getAssetHash(verifiedAssets[currentAssetIndex].assetAddress, verifiedAssets[currentAssetIndex].assetId);
        if (owners[assetHash] == address(0)) {
            prices[assetHash] = 0;
        }
        currentAssetIndex++;
        lastBidTime = block.timestamp;
        return true;
    }

    function bidderClaim(address asset, uint256 id) external notInAuction validAsset(asset) returns (bool) {
        bytes32 assetHash = getAssetHash(asset, id);
        require(owners[assetHash] == msg.sender, "Not the owner of the asset");
        ERC721(asset).safeTransferFrom(address(this), msg.sender, id);
        delete owners[assetHash];
        return true;
    }

    function sellerClaim(address asset, uint256 id) external notInAuction validAsset(asset) returns (bool) {
        bytes32 assetHash = getAssetHash(asset, id);
        require(sellers[assetHash] == msg.sender, "Not the owner of the asset");
        if (prices[assetHash] != 0) {
            AuctionToken(auctionTokenAddress).transfer(msg.sender, prices[assetHash]);
        } else {
            ERC721(asset).safeTransferFrom(address(this), msg.sender, id);
        }
        delete sellers[assetHash];
        delete prices[assetHash];
        return true;
    }

    function isNotInAuction() external view notInAuction returns (bool) {
        return true;
    }

    function isInAuction() external view inAuction returns (bool) {
        return true;
    }

    function getPendingAssets() external view notInAuction returns (Asset[] memory) {
        return pendingAssets;
    }

    function getVerifiedAssets() external view notInAuction returns (Asset[] memory) {
        return verifiedAssets;
    }

    function getCurrentAsset() external view inAuction returns (Asset memory) {
        return verifiedAssets[currentAssetIndex];
    }

    function getAssetPrice(address asset, uint256 id) external view validAsset(asset) returns (uint256) {
        return prices[getAssetHash(asset, id)];
    }

    function getAssetOwner(address asset, uint256 id) external view validAsset(asset) returns (address) {
        return owners[getAssetHash(asset, id)];
    }

    function getAssetSeller(address asset, uint256 id) external view validAsset(asset) returns (address) {
        return sellers[getAssetHash(asset, id)];
    }
}
