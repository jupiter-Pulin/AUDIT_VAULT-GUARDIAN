// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IVaultShares, IERC4626} from "../interfaces/IVaultShares.sol";
import {AaveAdapter, IPool} from "./investableUniverseAdapters/AaveAdapter.sol";
import {UniswapAdapter} from "./investableUniverseAdapters/UniswapAdapter.sol";
import {DataTypes} from "../vendor/DataTypes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VaultShares is
    ERC4626,
    IVaultShares,
    AaveAdapter,
    UniswapAdapter,
    ReentrancyGuard
{
    error VaultShares__DepositMoreThanMax(uint256 amount, uint256 max);
    error VaultShares__NotGuardian();
    error VaultShares__NotVaultGuardianContract();
    error VaultShares__AllocationNot100Percent(uint256 totalAllocation);
    error VaultShares__NotActive();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 internal immutable i_uniswapLiquidityToken;
    IERC20 internal immutable i_aaveAToken;
    address private immutable i_guardian;
    address private immutable i_vaultGuardians;
    uint256 private immutable i_guardianAndDaoCut;
    bool private s_isActive;

    AllocationData private s_allocationData;

    uint256 private constant ALLOCATION_PRECISION = 1_000;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event UpdatedAllocation(AllocationData allocationData);
    event NoLongerActive();
    event FundsInvested();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyGuardian() {
        if (msg.sender != i_guardian) {
            revert VaultShares__NotGuardian();
        }
        _;
    }

    modifier onlyVaultGuardians() {
        if (msg.sender != i_vaultGuardians) {
            revert VaultShares__NotVaultGuardianContract();
        }
        _;
    }

    modifier isActive() {
        if (!s_isActive) {
            revert VaultShares__NotActive();
        }
        _;
    }

    // slither-disable-start reentrancy-eth
    /**
     * @notice removes all supplied liquidity from Uniswap and supplied lending amount from Aave
     * and then re-invests it back into them only if the vault is active
     */
    modifier divestThenInvest() {
        uint256 uniswapLiquidityTokensBalance = i_uniswapLiquidityToken
            .balanceOf(address(this));
        uint256 aaveAtokensBalance = i_aaveAToken.balanceOf(address(this));

        // Divest
        //这个asset()是从哪里冒出来的？
        //e 由ERC4626继承而来 返回的是底层资产的地址
        if (uniswapLiquidityTokensBalance > 0) {
            _uniswapDivest(IERC20(asset()), uniswapLiquidityTokensBalance);
        }
        if (aaveAtokensBalance > 0) {
            _aaveDivest(IERC20(asset()), aaveAtokensBalance);
        }

        _;
        //written 这里的下划线意味着所有操作都完成后，在检查系统是否是活跃，如果是，将剩余的资金进行了在投资

        // Reinvest
        if (s_isActive) {
            //所有的投资都要经过此函数
            _investFunds(IERC20(asset()).balanceOf(address(this)));
        }
    }

    // slither-disable-end reentrancy-eth

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // We use a struct to avoid stack too deep errors. Thanks Solidity
    constructor(
        ConstructorData memory constructorData
    )
        ERC4626(constructorData.asset)
        ERC20(constructorData.vaultName, constructorData.vaultSymbol)
        //written aave这里mint不出任何东西，所以测试会是0
        AaveAdapter(constructorData.aavePool)
        //@written 所有的vaultshares测试都是基于wethvault，并没有测试usdc和link，一定有大问题,况且uniswap的投资是设计weth和usdc
        //@written 接着上面的注释说，由于uniswapadapter硬编码了函数，所以如果创建了link合约，实际的投资依然不过还是link和weth，并不影响，只是名称不同

        //written uniswap这里liquiditytoken是有mint的
        UniswapAdapter(
            constructorData.uniswapRouter,
            constructorData.weth,
            constructorData.usdc
        )
    {
        i_guardian = constructorData.guardian;
        i_guardianAndDaoCut = constructorData.guardianAndDaoCut;
        i_vaultGuardians = constructorData.vaultGuardians;
        s_isActive = true;
        updateHoldingAllocation(constructorData.allocationData);

        //written aave不是必须要存两个代币吗，这里只有一个资产该如何存入？uniswap类似
        //e 这并不是资产的交互，只是实例化aavetoken和uniswap的特定代币token
        //e aave不是uniswap，它只需要存一种代币即可，因为aave是借贷而不是流动性市场的提供
        // External calls
        i_aaveAToken = IERC20(
            IPool(constructorData.aavePool)
                .getReserveData(address(constructorData.asset))
                .aTokenAddress
        );
        //@audit-high 如果asset是weth，那么getpair只会返回weth/weth 就是一个错误的地址值      done
        i_uniswapLiquidityToken = IERC20(
            i_uniswapFactory.getPair(
                address(constructorData.asset),
                address(i_weth)
            )
        );
    }

    /**
     * @notice Sets the vault as not active, which means that the vault guardian has quit
     * @notice Users will not be able to invest in this vault, however, they will be able to withdraw their deposited assets
     */
    function setNotActive() public onlyVaultGuardians isActive {
        s_isActive = false;
        emit NoLongerActive();
    }

    /**
     * @notice Allows Vault Guardians to update their allocation ratio (and thus, their strategy of investment)
     * @param tokenAllocationData The new allocation data
     */
    function updateHoldingAllocation(
        AllocationData memory tokenAllocationData
    ) public onlyVaultGuardians isActive {
        uint256 totalAllocation = tokenAllocationData.holdAllocation +
            tokenAllocationData.uniswapAllocation +
            tokenAllocationData.aaveAllocation;
        //e total is 1000
        if (totalAllocation != ALLOCATION_PRECISION) {
            revert VaultShares__AllocationNot100Percent(totalAllocation);
        }
        //written update 策略后 让全局变量s_allocationData更新,如果此时有人调用deposit，redeem等会出发investFunds的函数，都会读取s_allocation
        //e yeah
        s_allocationData = tokenAllocationData;
        emit UpdatedAllocation(tokenAllocationData);
    }

    /**
     * @dev See {IERC4626-deposit}. Overrides the Openzeppelin implementation.
     *
     * @notice Mints shares to the DAO and the guardian as a fee
     */
    // slither-disable-start reentrancy-eth

    //written 我需要試著將用戶在withdrew和redeem,deposit時不斷的去update投資策略并且進行重新投資,試著寫個模糊測試吧。
    //如果测试有问题，可以试着先写uint=》deposit ，updateinvest，redeem @audit -? fuzz test be needed
    //written 如果我用非允许的代币进行质押会怎么办？
    //e 他是直接safetransferfrom，你余额里没有这个 若这个保险库为wethvault，那么你没有weth，你就会报错
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override(ERC4626, IERC4626)
        isActive
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) {
            //e type(uint256).max
            revert VaultShares__DepositMoreThanMax(
                assets,
                maxDeposit(receiver)
            );
        }

        uint256 shares = previewDeposit(assets);
        //@audit-high(done!!!) totalasset算的是本合约的价值，但是并没有计算投资的价值，即previewDeposit算的是shares= asset*totalSupply/totalAssets ，
        //如果你的asset原本为10，现在留在合约的只有5，那么 分配给你的shares会比之前的人更高
        //@ 注意 ，紧接上段：这会导致如果用户进行赎回或者withdraw，代码是直接基于=>assets=(shares*totalAssets)/totalSupply，如果totalasset减少，那么asset的值也会减少
        _deposit(_msgSender(), receiver, assets, shares);

        _mint(i_guardian, shares / i_guardianAndDaoCut);
        _mint(i_vaultGuardians, shares / i_guardianAndDaoCut);

        _investFunds(assets);
        return shares;
    }

    /**
     * @notice Invests user deposited assets into the investable universe (hold, Uniswap, or Aave) based on the allocation data set by the vault guardian
     * @param assets The amount of assets to invest
     */
    function _investFunds(uint256 assets) private {
        uint256 uniswapAllocation = (assets *
            s_allocationData.uniswapAllocation) / ALLOCATION_PRECISION; //1 ether*300/1000
        uint256 aaveAllocation = (assets * s_allocationData.aaveAllocation) /
            ALLOCATION_PRECISION;

        emit FundsInvested();
        _uniswapInvest(IERC20(asset()), uniswapAllocation);
        _aaveInvest(IERC20(asset()), aaveAllocation);
    }

    // slither-disable-start reentrancy-benign
    /*
     * @notice Unintelligently just withdraws everything, and then reinvests it all.
     * @notice Anyone can call this and pay the gas costs to rebalance the portfolio at any time.
     * @dev We understand that this is horrible for gas costs.
     */
    //written 任何人都有权利去rebalance，太荒谬了吧
    function rebalanceFunds() public isActive divestThenInvest nonReentrant {}

    /**
     * @dev See {IERC4626-withdraw}.
     *
     * We first divest our assets so we get a good idea of how many assets we hold.
     * Then, we redeem for the user, and automatically reinvest.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override(IERC4626, ERC4626)
        divestThenInvest
        nonReentrant
        returns (uint256)
    //written 如果有人在进行withdraw或者redeem时，又有人在deposit怎么办？
    //e OKAY
    {
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }

    /**
     * @dev See {IERC4626-redeem}.
     *
     * We first divest our assets so we get a good idea of how many assets we hold.
     * Then, we redeem for the user, and automatically reinvest.
     */
    //written 如果receiver和owner不是一个人的情况下，这种情形该怎么测试
    //@audit-high !!!这还真是一个大错误      done

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override(IERC4626, ERC4626)
        divestThenInvest
        nonReentrant
        returns (uint256)
    {
        uint256 assets = super.redeem(shares, receiver, owner);
        return assets;
    }

    // slither-disable-end reentrancy-eth
    // slither-disable-end reentrancy-benign

    /*//////////////////////////////////////////////////////////////
                             VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    /**
     * @return The guardian of the vault
     */
    function getGuardian() external view returns (address) {
        return i_guardian;
    }

    /**
     * @return The ratio of the amount in vaults that goes to the vault guardians and the DAO
     */
    function getGuardianAndDaoCut() external view returns (uint256) {
        return i_guardianAndDaoCut;
    }

    /**
     * @return Gets the address of the Vault Guardians protocol
     */
    function getVaultGuardians() external view returns (address) {
        return i_vaultGuardians;
    }

    /**
     * @return A bool indicating if the vault is active (has an active vault guardian and is accepting deposits) or not
     */
    function getIsActive() external view returns (bool) {
        return s_isActive;
    }

    /**
     * @return The Aave aToken for the vault's underlying asset
     */
    function getAaveAToken() external view returns (address) {
        return address(i_aaveAToken);
    }

    /**
     * @return Uniswap's LP token
     */
    function getUniswapLiquidtyToken() external view returns (address) {
        return address(i_uniswapLiquidityToken);
    }

    /**
     * @return The allocation data set by the vault guardian
     */
    function getAllocationData() external view returns (AllocationData memory) {
        return s_allocationData;
    }
}
