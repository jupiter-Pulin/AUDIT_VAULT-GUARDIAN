// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
import {console} from "forge-std/console.sol";
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {VaultShares, IERC20} from "../../../src/protocol/VaultShares.sol";

import {console2} from "forge-std/console2.sol";

contract VaultSharesTest is Base_Test {
    uint256 mintAmount = 100 ether;
    address guardian = makeAddr("guardian");
    address user = makeAddr("user");
    AllocationData allocationData =
        AllocationData(
            500, // hold
            250, // uniswap
            250 // aave
        );
    VaultShares public wethVaultShares;
    uint256 public defaultGuardianAndDaoCut = 1000;

    AllocationData newAllocationData =
        AllocationData(
            0, // hold
            500, // uniswap
            500 // aave
        );

    function setUp() public override {
        Base_Test.setUp();
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

    function testSetupVaultShares() public hasGuardian {
        assertEq(wethVaultShares.getGuardian(), guardian);
        assertEq(
            wethVaultShares.getGuardianAndDaoCut(),
            defaultGuardianAndDaoCut
        );
        assertEq(wethVaultShares.getVaultGuardians(), address(vaultGuardians));
        assertEq(wethVaultShares.getIsActive(), true);
        assertEq(wethVaultShares.getAaveAToken(), address(awethTokenMock));
        assertEq(
            address(wethVaultShares.getUniswapLiquidtyToken()),
            uniswapFactoryMock.getPair(address(weth), address(weth))
        );
    }

    function testSetNotActive() public hasGuardian {
        vm.prank(wethVaultShares.getVaultGuardians());
        wethVaultShares.setNotActive();
        assertEq(wethVaultShares.getIsActive(), false);
    }

    function testOnlyVaultGuardiansCanSetNotActive() public hasGuardian {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultShares.VaultShares__NotVaultGuardianContract.selector
            )
        );
        wethVaultShares.setNotActive();
    }

    function testOnlyCanSetNotActiveIfActive() public hasGuardian {
        vm.startPrank(wethVaultShares.getVaultGuardians());
        wethVaultShares.setNotActive();
        vm.expectRevert(
            abi.encodeWithSelector(VaultShares.VaultShares__NotActive.selector)
        );
        wethVaultShares.setNotActive();
        vm.stopPrank();
    }

    function testUpdateHoldingAllocation() public hasGuardian {
        vm.startPrank(wethVaultShares.getVaultGuardians());
        wethVaultShares.updateHoldingAllocation(newAllocationData);
        assertEq(
            wethVaultShares.getAllocationData().holdAllocation,
            newAllocationData.holdAllocation
        );
        assertEq(
            wethVaultShares.getAllocationData().uniswapAllocation,
            newAllocationData.uniswapAllocation
        );
        assertEq(
            wethVaultShares.getAllocationData().aaveAllocation,
            newAllocationData.aaveAllocation
        );
    }

    function testOnlyVaultGuardiansCanUpdateAllocationData()
        public
        hasGuardian
    {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultShares.VaultShares__NotVaultGuardianContract.selector
            )
        );
        wethVaultShares.updateHoldingAllocation(newAllocationData);
    }

    function testOnlyupdateAllocationDataWhenActive() public hasGuardian {
        vm.startPrank(wethVaultShares.getVaultGuardians());
        wethVaultShares.setNotActive();
        vm.expectRevert(
            abi.encodeWithSelector(VaultShares.VaultShares__NotActive.selector)
        );
        wethVaultShares.updateHoldingAllocation(newAllocationData);
        vm.stopPrank();
    }

    function testMustUpdateAllocationDataWithCorrectPrecision()
        public
        hasGuardian
    {
        AllocationData memory badAllocationData = AllocationData(0, 200, 500);
        uint256 totalBadAllocationData = badAllocationData.holdAllocation +
            badAllocationData.aaveAllocation +
            badAllocationData.uniswapAllocation;

        vm.startPrank(wethVaultShares.getVaultGuardians());
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultShares.VaultShares__AllocationNot100Percent.selector,
                totalBadAllocationData
            )
        );

        wethVaultShares.updateHoldingAllocation(badAllocationData);
        vm.stopPrank();
    }

    function testUserCanDepositFunds() public hasGuardian {
        weth.mint(mintAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        console2.log("mint amount is :", mintAmount); //1e20
        console2.log(
            "user balance of in wethvaultshares:",
            wethVaultShares.balanceOf(user)
        ); //2.671e20
        //written 爲什麽mintAmount后的值比投完資后的值還小？
        //e 這是整個mintamount以後給你的份額，就和aavetoken裏的底層資產與AToken之間有匯率一樣
        assert(wethVaultShares.balanceOf(user) > 0);
    }

    function testUserDepositsFundsAndDaoAndGuardianGetShares()
        public
        hasGuardian
    {
        uint256 startingGuardianBalance = wethVaultShares.balanceOf(guardian);
        uint256 startingDaoBalance = wethVaultShares.balanceOf(
            address(vaultGuardians)
        );

        weth.mint(mintAmount, user);
        vm.startPrank(user);
        console.log(wethVaultShares.totalSupply());
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);

        assert(wethVaultShares.balanceOf(guardian) > startingGuardianBalance);
        assert(
            wethVaultShares.balanceOf(address(vaultGuardians)) >
                startingDaoBalance
        );
    }

    modifier userIsInvested() {
        weth.mint(mintAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        vm.stopPrank();
        _;
    }

    function testRebalanceResultsInTheSameOutcome()
        public
        hasGuardian
        userIsInvested
    {
        uint256 startingUniswapLiquidityTokensBalance = IERC20(
            wethVaultShares.getUniswapLiquidtyToken()
        ).balanceOf(address(wethVaultShares));
        uint256 startingAaveAtokensBalance = IERC20(
            wethVaultShares.getAaveAToken()
        ).balanceOf(address(wethVaultShares));

        // address jupiterPu = makeAddr("jupiterPu");
        // weth.mint(1e18, jupiterPu);
        // vm.startPrank(jupiterPu);
        // weth.approve(address(wethVaultShares), 1e18);
        // wethVaultShares.deposit(1e18, jupiterPu);
        // vm.stopPrank();

        wethVaultShares.rebalanceFunds();

        assertEq(
            IERC20(wethVaultShares.getUniswapLiquidtyToken()).balanceOf(
                address(wethVaultShares)
            ),
            startingUniswapLiquidityTokensBalance
        );
        assertEq(
            IERC20(wethVaultShares.getAaveAToken()).balanceOf(
                address(wethVaultShares)
            ),
            startingAaveAtokensBalance
        );
        //written 爲什麽在兩次質押完成後，uniswapLiquidity token 是0呢？
        //e 因为liquiditytoken是uniswap的weth/weth，所以该池子是返回的0
        //written 那为什么aave返回的也是0？ 这个的投资为什么投不了
        //@audit 因为aavepool根本没有锻造功能，然后他的atoken自然就会为0（在此场景中atoken为awethmock）
    }

    function testWithdraw() public hasGuardian userIsInvested {
        uint256 startingBalance = weth.balanceOf(user);
        uint256 startingSharesBalance = wethVaultShares.balanceOf(user);
        uint256 amoutToWithdraw = 1 ether;

        vm.prank(user);
        wethVaultShares.withdraw(amoutToWithdraw, user, user);

        assertEq(weth.balanceOf(user), startingBalance + amoutToWithdraw);
        assert(wethVaultShares.balanceOf(user) < startingSharesBalance);
    }

    function testRedeem() public hasGuardian userIsInvested {
        uint256 startingBalance = weth.balanceOf(user);
        uint256 startingSharesBalance = wethVaultShares.balanceOf(user);
        uint256 amoutToRedeem = 1 ether;

        vm.prank(user);
        wethVaultShares.redeem(amoutToRedeem, user, user);

        assert(weth.balanceOf(user) > startingBalance);
        assertEq(
            wethVaultShares.balanceOf(user),
            startingSharesBalance - amoutToRedeem
        );
    }
}
