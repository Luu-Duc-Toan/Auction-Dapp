// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/DAO.sol";
import "../../src/AuctionManagement.sol";
import "../../src/AuctionToken.sol";
import "../../src/SampleAsset.sol";

contract DAOTest is Test {
    DAO public dao;
    AuctionManagement public auctionManagement;
    AuctionToken public auctionToken;
    SampleAsset public sampleAsset;

    address public owner;
    address public member1;
    address public member2;
    address public member3;
    address public seller;

    uint256 public startTime;
    uint256 public duration;
    uint256 public elapsedTime;
    uint256 public fairWarningTime;
    uint256 public graceTime;
    uint256 public period;

    function setUp() public {
        owner = makeAddr("owner");
        member1 = makeAddr("member1");
        member2 = makeAddr("member2");
        member3 = makeAddr("member3");
        seller = makeAddr("seller");

        // Setup member accounts
        vm.deal(member1, 10 ether);
        vm.deal(member2, 20 ether);
        vm.deal(member3, 30 ether);

        startTime = block.timestamp + 3600; // Start in the future
        duration = 3600; // 1 hour
        elapsedTime = 86400; // 1 day
        fairWarningTime = 60; // 1 minute
        graceTime = 600; // 10 minutes
        period = 1800; // 30 minutes

        vm.startPrank(owner);
        // Deploy contracts
        auctionManagement = new AuctionManagement(startTime, duration, elapsedTime, fairWarningTime);

        // Get the auction token
        address tokenAddr = auctionManagement.auctionTokenAddress();
        auctionToken = AuctionToken(tokenAddr);

        // Deploy DAO
        dao = new DAO(
            graceTime,
            period,
            51, // 51% quorum
            address(auctionManagement),
            address(auctionToken)
        );

        // Mint tokens to DAO for bidding
        auctionToken.mint(address(dao), 10000);

        // Create sample asset
        sampleAsset = new SampleAsset();
        vm.stopPrank();

        // Mint asset to seller
        vm.startPrank(owner);
        sampleAsset.mint(seller);
        // Mint asset to DAO for potential selling
        sampleAsset.mint(address(dao));
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(address(dao.auctionManagement()), address(auctionManagement));
        assertEq(address(dao.auctionToken()), address(auctionToken));
        assertEq(dao.graceTime(), graceTime);
        assertEq(dao.period(), period);
        assertEq(dao.quorum(), 51);
        assertEq(dao.totalProposals(), 0);
        assertEq(dao.treasury(), 0);
        assertEq(dao.totalShares(), 0);
    }

    function testJoinDAO() public {
        vm.startPrank(member1);
        dao.joinDAO{value: 5 ether}();
        vm.stopPrank();

        assertEq(dao.treasury(), 5 ether);
        assertEq(dao.totalShares(), 5 ether);
        assertEq(dao.shares(member1), 5 ether);

        vm.startPrank(member2);
        dao.joinDAO{value: 10 ether}();
        vm.stopPrank();

        assertEq(dao.treasury(), 15 ether);
        assertEq(dao.totalShares(), 15 ether);
        assertEq(dao.shares(member2), 10 ether);
    }

    function testQuitDAO() public {
        // Join first
        vm.startPrank(member1);
        dao.joinDAO{value: 5 ether}();
        uint256 initialBalance = member1.balance;

        // Then quit
        dao.quitDAO();
        vm.stopPrank();

        // Check balances
        assertEq(dao.treasury(), 0);
        assertEq(dao.totalShares(), 0);
        assertEq(dao.shares(member1), 0);
        assertEq(member1.balance, initialBalance + 5 ether);
    }

    function testCreateProposal() public {
        // Setup members
        vm.prank(member1);
        dao.joinDAO{value: 1 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 9 ether}();

        // Member2 has enough shares to propose (9/10 = 90%)
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 500); // Buy proposal
        vm.stopPrank();

        assertEq(dao.totalProposals(), 1);

        vm.startPrank(member1);
        dao.createProposal(address(sampleAsset), 1, false, 500); // Sell proposal
        vm.stopPrank();
    }

    function testVoting() public {
        // Setup members
        vm.prank(member1);
        dao.joinDAO{value: 3 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 7 ether}();

        // Create proposal
        vm.prank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 500); // Buy proposal

        // Members vote
        vm.prank(member1);
        dao.vote(0, true); // Yay

        vm.prank(member2);
        dao.vote(0, false); // Nay

        // Check cannot vote twice
        vm.expectRevert("Already voted on this proposal");
        vm.prank(member1);
        dao.vote(0, false);
    }

    function testBuyProposalExecution() public {
        // Setup auction with asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 300);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        // Setup DAO with members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Create buy proposal
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 500);

        // Vote on proposal
        dao.vote(0, true);
        vm.stopPrank();

        vm.prank(member1);
        dao.vote(0, true);

        // Start auction
        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // Execute bid after voting period + grace time
        vm.warp(block.timestamp + period + graceTime + 1);

        // Bid on behalf of DAO
        vm.prank(member1);
        dao.bid(0, 500);
    }

    function testSellProposalExecution() public {
        // Setup DAO with members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Create sell proposal for asset owned by DAO
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 1, false, 300);

        // Vote on proposal
        dao.vote(0, true);
        vm.stopPrank();

        vm.prank(member1);
        dao.vote(0, true);

        // Execute after voting period + grace time
        vm.warp(block.timestamp + period + graceTime + 1);

        // Submit asset to auction
        vm.prank(member1);
        dao.sell(0, 300);

        // Check asset was added to auction
        assertEq(auctionManagement.getAssetSeller(address(sampleAsset), 1), address(dao));
    }

    function testJoinDAOWithZeroValue() public {
        // Should revert when trying to join with 0 value
        vm.prank(member1);
        vm.expectRevert("Must send ether to join");
        dao.joinDAO{value: 0}();
    }

    function testQuitDAOWithoutShares() public {
        // Should revert when trying to quit without any shares
        vm.prank(member1);
        vm.expectRevert("No shares to withdraw");
        dao.quitDAO();
    }

    function testCreateProposalWithInsufficientShares() public {
        // Setup members but with insufficient shares
        vm.prank(member1);
        dao.joinDAO{value: 1 ether}();

        // Total shares will be 1 ether, requiring 0.51 ether to meet quorum
        // member1 has exactly 1 ether, which exceeds quorum requirement

        vm.prank(member3);
        dao.joinDAO{value: 20 ether}();

        // Now member1's share is too small (1/21 is about 4.7%)
        vm.prank(member1);
        vm.expectRevert("Not enough shares to propose");
        dao.createProposal(address(sampleAsset), 0, true, 500);
    }

    function testProposalVotedAgainst() public {
        // Setup members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Create buy proposal
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 500);

        // Vote against proposal
        dao.vote(0, false); // Member2 votes against (6 ETH)
        vm.stopPrank();

        vm.prank(member1);
        dao.vote(0, false); // Member1 also votes against (4 ETH)

        // Add asset to auction
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 300);
        vm.stopPrank();

        // Start auction
        vm.prank(owner);
        auctionManagement.verifyAsset(0);
        vm.warp(startTime);

        // Try to execute the proposal that was voted against
        vm.prank(member1);
        vm.expectRevert("Proposal was not approved");
        dao.bid(0, 500);
    }

    function testExecuteProposalDuringVotingPeriod() public {
        // Setup auction with asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 300);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        // Setup DAO members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Create buy proposal
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 500);

        // Vote on proposal
        dao.vote(0, true);
        vm.stopPrank();

        vm.prank(member1);
        dao.vote(0, true);

        // Start auction
        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        vm.warp(period / 2);
        // Try to bid on behalf of DAO during voting period
        vm.prank(member1);
        vm.expectRevert("Proposal is still opening");
        dao.bid(0, 500);
    }

    function testVoteOnNonExistentProposal() public {
        // Setup member
        vm.prank(member1);
        dao.joinDAO{value: 5 ether}();

        // Try to vote on a proposal that doesn't exist
        vm.prank(member1);
        vm.expectRevert("Invalid proposal ID");
        dao.vote(0, true);
    }

    function testVoteByNonMember() public {
        // Setup a member to create a proposal
        vm.prank(member1);
        dao.joinDAO{value: 10 ether}();

        // Create proposal
        vm.prank(member1);
        dao.createProposal(address(sampleAsset), 0, true, 500);

        // Try to vote from an address that doesn't have shares
        vm.prank(member3); // member3 has not joined the DAO
        vm.expectRevert("Must hold shares to vote");
        dao.vote(0, true);
    }

    function testSuccessfulClaimAfterWinningAuction() public {
        // Setup auction with asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 300);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        // Setup DAO members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Create buy proposal
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 500);

        // Vote on proposal
        dao.vote(0, true);
        vm.stopPrank();

        vm.prank(member1);
        dao.vote(0, true);

        // Start auction
        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // Execute bid after voting period + grace time
        vm.warp(block.timestamp + period + graceTime + 1);

        // Set up the auction state so the DAO wins
        vm.prank(address(dao));
        auctionToken.approve(address(auctionManagement), 500);

        // Mock the DAO winning the auction by manually bidding and closing auction
        vm.startPrank(address(dao));
        auctionManagement.bid(500);
        vm.stopPrank();

        // Wait for fair warning time
        vm.warp(block.timestamp + fairWarningTime + 1);

        // Owner gavels the auction
        vm.prank(owner);
        auctionManagement.gavel();

        // Close the auction
        vm.warp(startTime + duration + 1);
        vm.prank(owner);
        auctionManagement.closeAuction();

        // DAO claims the asset
        vm.prank(member1);
        dao.claim(0);

        // Verify DAO owns the asset
        assertEq(sampleAsset.ownerOf(0), address(dao));
    }

    function testNonExistentSellProposalExecution() public {
        // Setup DAO with members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Attempt to execute a non-existent proposal
        vm.warp(block.timestamp + period + graceTime + 1);

        vm.prank(member1);
        vm.expectRevert("Invalid proposal ID");
        dao.sell(999, 300); // Invalid proposal ID
    }

    function testClaimAssetDAODidntWin() public {
        // Setup auction with asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 9);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);

        // Setup DAO members
        vm.prank(member1);
        dao.joinDAO{value: 4 ether}();

        vm.prank(member2);
        dao.joinDAO{value: 6 ether}();

        // Create buy proposal
        vm.startPrank(member2);
        dao.createProposal(address(sampleAsset), 0, true, 9);

        // Vote on proposal
        dao.vote(0, true);
        vm.stopPrank();

        vm.prank(member1);
        dao.vote(0, true);

        // Start auction
        vm.warp(startTime);
        vm.prank(owner);
        auctionManagement.beginAuction();

        // Wait for voting period + grace time to end
        vm.warp(block.timestamp + period + graceTime + 1);

        // Someone else wins the auction, not the DAO
        vm.startPrank(owner);
        address winningBidder = makeAddr("winningBidder");
        auctionToken.mint(winningBidder, 10);
        vm.stopPrank();
        vm.startPrank(winningBidder);
        auctionToken.approve(address(auctionManagement), 10);
        auctionManagement.bid(10);
        vm.stopPrank();

        // Wait for fair warning time
        vm.warp(block.timestamp + fairWarningTime + 1);

        // Owner gavels the auction
        vm.prank(owner);
        auctionManagement.gavel();

        // Close the auction
        vm.warp(startTime + duration + 1);
        vm.prank(owner);
        auctionManagement.closeAuction();

        // Try to claim the asset from a proposal that didn't win
        vm.prank(member1);
        vm.expectRevert(); // Should revert because DAO wasn't the highest bidder
        dao.claim(0);
    }
}
