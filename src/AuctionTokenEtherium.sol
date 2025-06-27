// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@arbitrum/nitro-contracts/src/bridge/Inbox.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./AuctionTokenArbitrum.sol";

contract AuctionTokenEtherium is ERC20, Ownable {
    address public inbox;
    address public outbox;
    address public arbitrumTarget;

    modifier onlyOutbox() {
        require(msg.sender == outbox, "Caller is not the outbox");
        _;
    }

    constructor(address _inbox, address _outbox, address _arbitrumTarget)
        ERC20("AuctionToken", "ATK")
        Ownable(msg.sender)
    {
        inbox = _inbox;
        outbox = _outbox;
        arbitrumTarget = _arbitrumTarget;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function withdraw(address caller, uint256 amount) external onlyOutbox {
        _mint(caller, amount);
    }

    function deposit(uint256 amount, uint256 maxSubmissionCost, uint256 maxGas, uint256 gasPriceBid)
        external
        payable
        onlyOutbox
        returns (uint256 ticketID)
    {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        bytes memory data = abi.encodeWithSelector(AuctionTokenArbitrum.deposit.selector, msg.sender, amount);
        ticketID = IInbox(inbox).createRetryableTicket{value: msg.value}(
            arbitrumTarget, 0, maxSubmissionCost, msg.sender, msg.sender, maxGas, gasPriceBid, data
        );
    }
}
