// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./AuctionTokenEtherium.sol";

contract AuctionTokenArbitrum is ERC20, Ownable {
    ArbSys constant arbsys = ArbSys(address(100));
    address immutable etheriumTarget;

    modifier onlyEtheriumTarget() {
        require(msg.sender == etheriumTarget, "Caller is not the Etherium target");
        _;
    }

    constructor(address _etheriumTarget) ERC20("AuctionToken", "ATK") Ownable(msg.sender) {
        etheriumTarget = AddressAliasHelper.applyL1ToL2Alias(_etheriumTarget);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function withdraw(uint256 amount) external returns (uint256 messageNumber) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        bytes memory data = abi.encodeWithSelector(AuctionTokenEtherium.withdraw.selector, msg.sender, amount);
        messageNumber = arbsys.sendTxToL1(etheriumTarget, data);
    }

    function deposit(address caller, uint256 amount) external onlyEtheriumTarget {
        _mint(caller, amount);
    }
}
