// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//@audit-info 此接口毫無意義，無人使用 done
interface IInvestableUniverseAdapter {
    // function invest(IERC20 token, uint256 amount) external;
    // function divest(IERC20 token, uint256 amount) external;
}
