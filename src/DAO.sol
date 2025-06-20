//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AuctionManagement.sol";
import "./AuctionToken.sol";

contract DAO {
    AuctionManagement public auctionManagement;
    AuctionToken public auctionToken;

    uint256 public treasury;
    uint256 public totalShares;
    uint256 public totalProposals;
    uint256 public graceTime;
    uint256 public period;
    uint256 public quorum;
    mapping(address => uint256) public shares;
    mapping(address => bool)[] public votes;
    AuctionManagement.Asset[] public assets;
    uint256[] public startTimes;
    uint256[] public prices;
    uint256[] public yayVotes;
    uint256[] public nayVotes;
    bool[] public isBuyings;
    bool[] public proposalStatus;

    constructor(
        uint256 _graceTime,
        uint256 _period,
        uint256 _quorum,
        address _auctionManagement,
        address _auctionToken
    ) {
        require(_quorum > 0 && _quorum <= 100, "Quorum must be between 1 and 100");
        require(_period > 0, "Period must be greater than 0");

        auctionManagement = AuctionManagement(_auctionManagement);
        auctionToken = AuctionToken(_auctionToken);

        graceTime = _graceTime;
        period = _period;
        quorum = _quorum;
    }

    event BidFailed(string reason);

    function joinDAO() public payable {
        require(msg.value > 0, "Must send ether to join");

        treasury += msg.value;
        shares[msg.sender] += msg.value;
        totalShares += msg.value;
    }

    function quitDAO() public {
        require(shares[msg.sender] > 0, "No shares to withdraw");

        uint256 share = shares[msg.sender];
        uint256 amount = (share * treasury) / totalShares;
        shares[msg.sender] = 0;
        treasury -= amount;
        totalShares -= share;
        payable(msg.sender).transfer(amount);
    }

    function createProposal(address assetAddress, uint256 assetId, bool isBuying, uint256 price) public {
        require(shares[msg.sender] >= totalShares / 10, "Not enough shares to propose");
        if (!isBuying) {
            require(ERC721(assetAddress).ownerOf(assetId) == address(this), "Must own the asset to sell");
        }

        votes.push();
        assets.push(AuctionManagement.Asset(assetAddress, assetId));
        startTimes.push(block.timestamp);
        prices.push(price);
        isBuyings.push(isBuying);
        yayVotes.push(0);
        nayVotes.push(0);
        proposalStatus.push(false);
        totalProposals++;
    }

    function vote(uint256 proposalId, bool voteYay) public {
        require(proposalId < totalProposals, "Invalid proposal ID");
        require(shares[msg.sender] > 0, "Must hold shares to vote");
        require(!votes[proposalId][msg.sender], "Already voted on this proposal");
        require(block.timestamp >= startTimes[proposalId], "Voting period has not started");
        require(block.timestamp < startTimes[proposalId] + period, "Voting period has ended");

        votes[proposalId][msg.sender] = true;
        if (voteYay) {
            yayVotes[proposalId] += shares[msg.sender];
        } else {
            nayVotes[proposalId] += shares[msg.sender];
        }
    }

    modifier isClosedProposal(uint256 proposalId) {
        require(proposalId < totalProposals, "Invalid proposal ID");
        require(!proposalStatus[proposalId], "Proposal already executed");
        require(block.timestamp >= startTimes[proposalId] + period + graceTime, "Proposal is still opening");
        _;
    }

    function bid(uint256 proposalId, uint256 price) public isClosedProposal(proposalId) {
        require(isBuyings[proposalId], "Proposal is not for buying");
        AuctionManagement.Asset memory asset = assets[proposalId];
        AuctionManagement.Asset memory currentAsset = auctionManagement.getCurrentAsset();
        require(
            currentAsset.assetAddress == asset.assetAddress && currentAsset.assetId == asset.assetId,
            "Not the current asset"
        );
        require(
            auctionManagement.getAssetOwner(asset.assetAddress, asset.assetId) != address(this),
            "Asset already owned by DAO"
        );
        if (price >= auctionManagement.getAssetPrice(currentAsset.assetAddress, currentAsset.assetId)) {
            proposalStatus[proposalId] = true;
            revert("Bid price must be greater than or equal to current price");
        }
        auctionToken.approve(address(auctionManagement), price);
        auctionManagement.bid(price);
    }

    function sell(uint256 proposalId, uint256 price) public isClosedProposal(proposalId) {
        require(!isBuyings[proposalId], "Proposal is not for selling");
        AuctionManagement.Asset memory asset = assets[proposalId];
        ERC721(asset.assetAddress).approve(address(auctionManagement), asset.assetId);
        auctionManagement.addAsset(asset.assetAddress, asset.assetId, price);
    }

    function claim(uint256 proposalId) public isClosedProposal(proposalId) {
        require(auctionManagement.isNotInAuction(), "Auction is still ongoing");
        AuctionManagement.Asset memory asset = assets[proposalId];

        if (isBuyings[proposalId]) {
            address currentOwner = auctionManagement.getAssetOwner(asset.assetAddress, asset.assetId);
            require(currentOwner != address(0), "Asset does not exist");

            if (currentOwner != address(this)) {
                emit BidFailed("Asset is not owned by DAO");
            } else {
                auctionManagement.bidderClaim(asset.assetAddress, asset.assetId);
            }
        } else {
            address currentSeller = auctionManagement.getAssetSeller(asset.assetAddress, asset.assetId);
            require(currentSeller == address(this), "Asset is not owned by DAO");
            auctionManagement.sellerClaim(asset.assetAddress, asset.assetId);
        }

        proposalStatus[proposalId] = true;
    }
}
