// SPDX-Liciense-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract SampleProduct is ERC721, Ownable {
    uint256 public nextTokenId;

    constructor() ERC721("SampleProduct", "SP") Ownable(msg.sender) {}

    function mint(address to) external onlyOwner {
        _safeMint(to, nextTokenId);
        nextTokenId++;
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }
}
