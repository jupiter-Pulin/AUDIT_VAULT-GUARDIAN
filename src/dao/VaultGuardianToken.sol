// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultGuardianToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    //written 从合约是没有煅烧功能的 意味着vaultGuardianToken无法被销毁，即使基金经理人退出项目，仍然会保留投票权
    //written 攻击者可以先成为守护者后立刻退出，积累了vgtoken用于操纵社区进行对他们有利的投票
    //@audit-? maybe high !!! needs prove
    constructor()
        ERC20("VaultGuardianToken", "VGT")
        ERC20Permit("VaultGuardianToken")
        Ownable(msg.sender)
    {}

    // The following functions are overrides required by Solidity.
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(
        address ownerOfNonce
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(ownerOfNonce);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
