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
    address public attacker = makeAddr("attacker");
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

    function testFactoryPairIsRouter() public {
        address pair = uniswapFactoryMock.getPair(address(weth), address(usdc));
        assertEq(pair, uniswapRouter);
    }

    function testDepositWithUnapprovedToken() public hasGuardian {
        ERC20Mock unkownToken = new ERC20Mock();
        unkownToken.mint(mintAmount, user);
        vm.startPrank(user);

        unkownToken.approve(address(wethVaultShares), mintAmount);
        weth.approve(address(wethVaultShares), mintAmount); //因为是wethvault要approve weth
        vm.expectRevert(); //不充分余额
        wethVaultShares.deposit(mintAmount, user);
    }

    function testTotalAssetIsNearlyWrong() public hasGuardian {
        uint256 totalAsset = wethVaultShares.totalAssets();
        //！！！！！注意，源代码这里显示的是3.75ETH，因为uni的错误addliquidity处理导致多抽走了1.25ether
        //因为adapter合约被vaultshares继承，所以因为其合约里还要50ether的 hold策略合约，所以会率先抽走这一部分
        assertEq(totalAsset, 5 ether); //整个的总供应量分为 2:1:1 =>hold =mintAmount*0.5=50 ether
        weth.mint(mintAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        uint256 sharesUser = wethVaultShares.deposit(mintAmount, user);
        vm.stopPrank();
        address Alice = makeAddr("Alice"); //make another user ,因为guardian是通过另一个合约而不是在vaultshares中进行deposit，所以shares不好查
        weth.mint(mintAmount, Alice);
        vm.startPrank(Alice);
        weth.approve(address(wethVaultShares), mintAmount);
        uint256 sharesAlice = wethVaultShares.deposit(mintAmount, Alice);
        vm.stopPrank();
        console2.log(
            "guardian shares  is :",
            wethVaultShares.balanceOf(guardian)
        ); //1059 3710 5454 5454 5453 =》10.01 ether(mint) + 0.2672 ether(user 分红) + 0.26745 ether（alice分红） ≈ 10.54465 ether。
        console2.log("sharesUser is :", sharesUser);
        console2.log("sharesAlice is :", sharesAlice);
    }

    function testConstantlyWithdrawAndDepositAndRedeem() public hasGuardian {
        //因为liquitity token 和aavetoken返回的都是0 ，所以自动跳过将代币取回的代码，所以所有的取回操作都是按照池子目前的量
        //user deposit
        weth.mint(mintAmount, user);
        uint256 userWethBalanceBefore = weth.balanceOf(user); //100ether
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        //user redeem
        uint256 maxShares = wethVaultShares.maxRedeem(user);

        wethVaultShares.redeem(maxShares, user, user);
        uint256 userWethBalanceAfter = weth.balanceOf(user); //52 ether 注意，这里的结果都是uniadapter的addliquidity 的值正确，即将amounts[0]删掉输出的结果
        console2.log("userWethBalanceAfter", userWethBalanceAfter);
        assert(userWethBalanceAfter < userWethBalanceBefore);

        vm.stopPrank();
    }

    function testMaliciousGuardianTakeOverTheDAO() public {
        address maliciousGuardian = makeAddr("maliciousGuardian");
        weth.mint(mintAmount, maliciousGuardian);
        //看看之前的vg
        uint256 vgTokenBefore = vaultGuardianToken.balanceOf(maliciousGuardian);
        vm.startPrank(maliciousGuardian);
        weth.approve(address(vaultGuardians), mintAmount);
        for (uint256 i = 0; i < 10; i++) {
            address maliciousGuardianWethVault = vaultGuardians.becomeGuardian(
                allocationData
            );
            //quit
            IERC20(maliciousGuardianWethVault).approve(
                address(vaultGuardians),
                1.001e19
            );
            vaultGuardians.quitGuardian();
        }
        uint256 vgTokenAfter = vaultGuardianToken.balanceOf(maliciousGuardian);
        console2.log("vgTokenBefore is :", vgTokenBefore); //0
        console2.log("vgTokenAfter is :", vgTokenAfter); //10e18
        assert(vgTokenAfter > vgTokenBefore);
        vm.stopPrank();
    }

    function testAttakcerFrokTheReceiverToUserRedeem() public hasGuardian {
        //user deposit
        weth.mint(mintAmount, user);
        uint256 userWethBalanceBefore = weth.balanceOf(user); //100ether
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        //attacker  redeem
        uint256 maxShares = wethVaultShares.maxRedeem(user);
        //这里的reveiver attakcer冒充！！！！
        wethVaultShares.redeem(maxShares, attacker, user);
        uint256 userWethBalanceAfter = weth.balanceOf(user); //0 ether
        console2.log("attacker balance after ", weth.balanceOf(attacker)); //52 ether    注意，这里的结果都是adapter的addliquidity 的值正确，即将amounts[0]删掉输出的结果
        console2.log("userWethBalanceAfter", userWethBalanceAfter);
        assert(userWethBalanceAfter < userWethBalanceBefore);

        vm.stopPrank();
    }

    function testAttackerFrokTheReceiverToUserWithdraw() public hasGuardian {
        //user deposit
        weth.mint(mintAmount, user);
        uint256 userWethBalanceBefore = weth.balanceOf(user); //100ether
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        //attacker  redeem
        uint256 maxAssets = wethVaultShares.maxWithdraw(user);
        //这里的reveiver attakcer冒充！！！！
        wethVaultShares.withdraw(maxAssets, attacker, user);
        uint256 userWethBalanceAfter = weth.balanceOf(user); //0 ether
        console2.log("attacker balance after ", weth.balanceOf(attacker)); //52 ether 注意，这里的结果都是adapter的addliquidity 的值正确，即将amounts[0]删掉输出的结果
        console2.log("userWethBalanceAfter", userWethBalanceAfter);
        assert(userWethBalanceAfter < userWethBalanceBefore);

        vm.stopPrank();
    }
}
