// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, 1e30);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
