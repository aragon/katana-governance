// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockVKatERC721 is ERC721 {
    uint256 private _nextTokenId = 1;

    constructor() ERC721("MockVKat", "VKAT") { }

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function isApprovedOrOwner(uint256 tokenId) external view returns (bool) {
        return _isApprovedOrOwner(msg.sender, tokenId);
    }
}
