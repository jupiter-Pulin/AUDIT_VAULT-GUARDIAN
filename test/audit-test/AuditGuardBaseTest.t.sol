// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../Base.t.sol";
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {IERC20} from "../../../src/protocol/VaultGuardians.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {VaultGuardiansBase} from "../../../src/protocol/VaultGuardiansBase.sol";

import {VaultGuardians} from "../../../src/protocol/VaultGuardians.sol";
import {VaultGuardianGovernor} from "../../../src/dao/VaultGuardianGovernor.sol";
import {VaultGuardianToken} from "../../../src/dao/VaultGuardianToken.sol";
import {console2} from "forge-std/console2.sol";

contract VaultGuardiansBaseTest is Base_Test {
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");
    VaultShares public wethVaultShares;
    VaultShares public usdcVaultShares;
    VaultShares public linkVaultShares;

    uint256 guardianAndDaoCut;
    uint256 stakePrice;
    uint256 mintAmount = 100 ether;

    // 500 hold, 250 uniswap, 250 aave
    AllocationData allocationData = AllocationData(500, 250, 250);
    AllocationData newAllocationData = AllocationData(0, 500, 500);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event GuardianAdded(address guardianAddress, IERC20 token);
    event GaurdianRemoved(address guardianAddress, IERC20 token);
    event InvestedInGuardian(
        address guardianAddress,
        IERC20 token,
        uint256 amount
    );
    event DinvestedFromGuardian(
        address guardianAddress,
        IERC20 token,
        uint256 amount
    );
    event GuardianUpdatedHoldingAllocation(
        address guardianAddress,
        IERC20 token
    );

    function setUp() public override {
        Base_Test.setUp();
        guardianAndDaoCut = vaultGuardians.getGuardianAndDaoCut();
        stakePrice = vaultGuardians.getGuardianStakePrice();
    }

    modifier hasGuardian() {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        _;
    }

    function testTokenGuardianTokenTwoNameAndSymbol() public hasGuardian {
        link.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        link.approve(address(vaultGuardians), mintAmount);

        vm.expectEmit(false, false, false, true, address(vaultGuardians));
        emit GuardianAdded(guardian, link);
        address tokenVault = vaultGuardians.becomeTokenGuardian(
            allocationData,
            link
        );
        linkVaultShares = VaultShares(tokenVault);
        vm.stopPrank();

        console2.log("token name is :", linkVaultShares.name()); // prints USDC
        console2.log("asset is :", linkVaultShares.asset()); // link addr
        assertEq(linkVaultShares.asset(), address(link));
    }
}
