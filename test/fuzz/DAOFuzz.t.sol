// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/DAO.sol";
import "../../src/AuctionManagement.sol";
import "../../src/AuctionToken.sol";
import "../../src/SampleAsset.sol";

contract DAOFuzzTest is Test {
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
    uint256 public quorum;

    function setUp() public {
        owner = makeAddr("owner");
        member1 = makeAddr("member1");
        member2 = makeAddr("member2");
        member3 = makeAddr("member3");
        seller = makeAddr("seller");

        // Setup member accounts
        vm.deal(member1, 100 ether);
        vm.deal(member2, 100 ether);
        vm.deal(member3, 100 ether);
        vm.deal(seller, 10 ether);

        startTime = block.timestamp + 3600; // Start in the future
        duration = 3600; // 1 hour
        elapsedTime = 86400; // 1 day
        fairWarningTime = 60; // 1 minute
        graceTime = 600; // 10 minutes
        period = 1800; // 30 minutes
        quorum = 51; // 51% quorum

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
            quorum,
            address(auctionManagement),
            address(auctionToken)
        );

        // Mint tokens to DAO for bidding
        auctionToken.mint(address(dao), 1000000);

        // Create sample asset
        sampleAsset = new SampleAsset();
        
        // Mint assets
        sampleAsset.mint(seller); // ID 0 for seller
        sampleAsset.mint(address(dao)); // ID 1 for DAO
        vm.stopPrank();

        // Setup auction with asset
        vm.startPrank(seller);
        sampleAsset.approve(address(auctionManagement), 0);
        auctionManagement.addAsset(address(sampleAsset), 0, 300);
        vm.stopPrank();

        vm.prank(owner);
        auctionManagement.verifyAsset(0);
    }

    // Test joining DAO with fuzzed ETH amounts
    function testFuzz_JoinDAO(uint256 amount) public {
        // Bound amount to be non-zero and not exceed member's balance
        amount = bound(amount, 1, 50 ether);
        
        vm.startPrank(member1);
        dao.joinDAO{value: amount}();
        vm.stopPrank();

        assertEq(dao.treasury(), amount);
        assertEq(dao.totalShares(), amount);
        assertEq(dao.shares(member1), amount);
    }
    
    // Test quitting DAO with fuzzed initial investment
    function testFuzz_QuitDAO(uint256 amount) public {
        // Bound amount to be reasonable
        amount = bound(amount, 1 ether, 50 ether);
        
        vm.startPrank(member1);
        dao.joinDAO{value: amount}();
        
        uint256 initialBalance = member1.balance;
        dao.quitDAO();
        vm.stopPrank();
        
        // Verify member got back their ETH
        assertEq(dao.treasury(), 0);
        assertEq(dao.totalShares(), 0);
        assertEq(dao.shares(member1), 0);
        assertEq(member1.balance, initialBalance + amount);
    }
    
    // Test proposal creation with different share distributions
    function testFuzz_CreateProposal(uint256 member1Shares, uint256 member2Shares) public {
        // Bound shares to reasonable values
        member1Shares = bound(member1Shares, 1 ether, 40 ether);
        member2Shares = bound(member2Shares, 1 ether, 40 ether);
        
        vm.prank(member1);
        dao.joinDAO{value: member1Shares}();
        
        vm.prank(member2);
        dao.joinDAO{value: member2Shares}();
        
        uint256 totalShares = member1Shares + member2Shares;
        uint256 quorumShares = (totalShares * quorum) / 100;
        
        // Create proposal from member that has enough shares
        if (member1Shares >= quorumShares) {
            vm.prank(member1);
            dao.createProposal(address(sampleAsset), 0, true, 500);
            assertEq(dao.totalProposals(), 1);
        } else if (member2Shares >= quorumShares) {
            vm.prank(member2);
            dao.createProposal(address(sampleAsset), 0, true, 500);
            assertEq(dao.totalProposals(), 1);
        }
    }
    
    // Test voting with different share weights
    function testFuzz_Voting(uint256 member1Shares, uint256 member2Shares, bool member1VoteYay) public {
        // Bound shares to reasonable values
        member1Shares = bound(member1Shares, 1 ether, 40 ether);
        member2Shares = bound(member2Shares, 1 ether, 40 ether);
        
        // Setup members
        vm.prank(member1);
        dao.joinDAO{value: member1Shares}();
        
        vm.prank(member2);
        dao.joinDAO{value: member2Shares}();
        
        // Create proposal
        uint256 totalShares = member1Shares + member2Shares;
        uint256 quorumShares = (totalShares * quorum) / 100;
        
        // Only create proposal if one member has enough shares
        if (member1Shares >= quorumShares || member2Shares >= quorumShares) {
            if (member1Shares >= quorumShares) {
                vm.prank(member1);
                dao.createProposal(address(sampleAsset), 0, true, 500);
            } else {
                vm.prank(member2);
                dao.createProposal(address(sampleAsset), 0, true, 500);
            }
            
            // Member 1 votes
            vm.prank(member1);
            dao.vote(0, member1VoteYay);
            
            // Member 2 always votes yay
            vm.prank(member2);
            dao.vote(0, true);
            
            // Check vote tallies
            if (member1VoteYay) {
                assertEq(dao.yayVotes(0), member1Shares + member2Shares);
                assertEq(dao.nayVotes(0), 0);
            } else {
                assertEq(dao.yayVotes(0), member2Shares);
                assertEq(dao.nayVotes(0), member1Shares);
            }
        }
    }
}
