/**
 *  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _
 * |_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_|
 * |_|                                                                                          |_|
 * |_| █████   █████                      ████   █████                                          |_|
 * |_|░░███   ░░███                      ░░███  ░░███                                           |_|
 * |_| ░███    ░███   ██████   █████ ████ ░███  ███████                                         |_|
 * |_| ░███    ░███  ░░░░░███ ░░███ ░███  ░███ ░░░███░                                          |_|
 * |_| ░░███   ███    ███████  ░███ ░███  ░███   ░███                                           |_|
 * |_|  ░░░█████░    ███░░███  ░███ ░███  ░███   ░███ ███                                       |_|
 * |_|    ░░███     ░░████████ ░░████████ █████  ░░█████                                        |_|
 * |_|     ░░░       ░░░░░░░░   ░░░░░░░░ ░░░░░    ░░░░░                                         |_|
 * |_|                                                                                          |_|
 * |_|                                                                                          |_|
 * |_|                                                                                          |_|
 * |_|   █████████                                     █████  ███                               |_|
 * |_|  ███░░░░░███                                   ░░███  ░░░                                |_|
 * |_| ███     ░░░  █████ ████  ██████   ████████   ███████  ████   ██████   ████████    █████  |_|
 * |_|░███         ░░███ ░███  ░░░░░███ ░░███░░███ ███░░███ ░░███  ░░░░░███ ░░███░░███  ███░░   |_|
 * |_|░███    █████ ░███ ░███   ███████  ░███ ░░░ ░███ ░███  ░███   ███████  ░███ ░███ ░░█████  |_|
 * |_|░░███  ░░███  ░███ ░███  ███░░███  ░███     ░███ ░███  ░███  ███░░███  ░███ ░███  ░░░░███ |_|
 * |_| ░░█████████  ░░████████░░████████ █████    ░░████████ █████░░████████ ████ █████ ██████  |_|
 * |_|  ░░░░░░░░░    ░░░░░░░░  ░░░░░░░░ ░░░░░      ░░░░░░░░ ░░░░░  ░░░░░░░░ ░░░░ ░░░░░ ░░░░░░   |_|
 * |_| _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _ |_|
 * |_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_|
 */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {VaultShares} from "./VaultShares.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//@audit-info 不符合最佳实践，建议直接从IVAULTDATA中 import
import {IVaultShares, IVaultData} from "../interfaces/IVaultShares.sol";
import {AStaticTokenData, IERC20} from "../abstract/AStaticTokenData.sol";
import {VaultGuardianToken} from "../dao/VaultGuardianToken.sol";

/*
 * @title VaultGuardiansBase
 * @author Vault Guardian
 * @notice This contract is the base contract for the VaultGuardians contract.
 * @notice it includes all the functionality of a user or guardian interacting with the protocol
 */

contract VaultGuardiansBase is AStaticTokenData, IVaultData {
    using SafeERC20 for IERC20;

    error VaultGuardiansBase__NotEnoughWeth(
        uint256 amount,
        uint256 amountNeeded
    );
    error VaultGuardiansBase__NotAGuardian(
        address guardianAddress,
        IERC20 token
    );
    error VaultGuardiansBase__CantQuitGuardianWithNonWethVaults(
        address guardianAddress
    );
    error VaultGuardiansBase__CantQuitWethWithThisFunction();
    error VaultGuardiansBase__TransferFailed();
    error VaultGuardiansBase__FeeTooSmall(uint256 fee, uint256 requiredFee);
    error VaultGuardiansBase__NotApprovedToken(address token);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address private immutable i_aavePool;
    address private immutable i_uniswapV2Router;
    VaultGuardianToken private immutable i_vgToken;

    //@audit-gas never been use ,請把其刪除 done
    uint256 private constant GUARDIAN_FEE = 0.1 ether;

    // DAO updatable values
    uint256 internal s_guardianStakePrice = 10 ether;
    //written 这个的费率是多少？
    //e 0.1%
    uint256 internal s_guardianAndDaoCut = 1000;

    // The guardian's address mapped to the asset, mapped to the allocation data
    //written asset means underlying？
    //e yeah
    mapping(address guardianAddress => mapping(IERC20 asset => IVaultShares vaultShares))
        private s_guardians;
    mapping(address token => bool approved) private s_isApprovedToken;

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

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyGuardian(IERC20 token) {
        if (address(s_guardians[msg.sender][token]) == address(0)) {
            revert VaultGuardiansBase__NotAGuardian(msg.sender, token);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address aavePool,
        address uniswapV2Router,
        address weth,
        address tokenOne, // USDC
        address tokenTwo, // LINK
        address vgToken
    ) AStaticTokenData(weth, tokenOne, tokenTwo) {
        s_isApprovedToken[weth] = true;
        s_isApprovedToken[tokenOne] = true;
        s_isApprovedToken[tokenTwo] = true;

        i_aavePool = aavePool;
        i_uniswapV2Router = uniswapV2Router;
        i_vgToken = VaultGuardianToken(vgToken);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice allows a user to become a guardian
     * @notice they have to send an ETH amount equal to the fee, and a WETH amount equal to the stake price
     *
     * @param wethAllocationData the allocation data for the WETH vault
     */
    function becomeGuardian(
        AllocationData memory wethAllocationData
    ) external returns (address) {
        //written 难道不需要检查用户是否有足够的weth成为guardian？
        //e 后面的_becomeTokenGuardian有调用safetransferfrom函数
        VaultShares wethVault = new VaultShares(
            IVaultShares.ConstructorData({
                asset: i_weth,
                vaultName: WETH_VAULT_NAME,
                vaultSymbol: WETH_VAULT_SYMBOL,
                guardian: msg.sender,
                allocationData: wethAllocationData,
                aavePool: i_aavePool,
                uniswapRouter: i_uniswapV2Router,
                guardianAndDaoCut: s_guardianAndDaoCut,
                vaultGuardians: address(this),
                weth: address(i_weth),
                usdc: address(i_tokenOne)
            })
        );
        return _becomeTokenGuardian(i_weth, wethVault);
    }

    /**
     * @notice Allows anyone to become a vault guardian for any one of the other supported tokens (USDC, LINK)
     * @notice However, only WETH vault guardians can become vault guardians for other tokens
     * @param allocationData A struct indicating the ratio of asset tokens to hold, invest in Aave and Uniswap (based on Vault Guardian strategy)
     * @param token The token to become a Vault Guardian for
     */
    function becomeTokenGuardian(
        AllocationData memory allocationData,
        IERC20 token
    ) external onlyGuardian(i_weth) returns (address) {
        //slither-disable-next-line uninitialized-local
        //written 为什么不考虑将tokenVault与上面的wethVault 合并
        //e 這是三個不同的合约实例，一个合约代表着一个保险库（以及一个基金经理）这不是一个可以用来当作全局变量的例子
        VaultShares tokenVault;
        if (address(token) == address(i_tokenOne)) {
            tokenVault = new VaultShares(
                IVaultShares.ConstructorData({
                    asset: token,
                    vaultName: TOKEN_ONE_VAULT_NAME,
                    vaultSymbol: TOKEN_ONE_VAULT_SYMBOL,
                    guardian: msg.sender,
                    allocationData: allocationData,
                    aavePool: i_aavePool,
                    uniswapRouter: i_uniswapV2Router,
                    guardianAndDaoCut: s_guardianAndDaoCut,
                    vaultGuardians: address(this),
                    weth: address(i_weth),
                    usdc: address(i_tokenOne)
                })
            );
        } else if (address(token) == address(i_tokenTwo)) {
            tokenVault = new VaultShares(
                IVaultShares.ConstructorData({
                    asset: token,
                    //@audit-low/medium mix-up the Name and symbol  done
                    vaultName: TOKEN_ONE_VAULT_NAME,
                    vaultSymbol: TOKEN_ONE_VAULT_SYMBOL,
                    guardian: msg.sender,
                    allocationData: allocationData,
                    aavePool: i_aavePool,
                    uniswapRouter: i_uniswapV2Router,
                    guardianAndDaoCut: s_guardianAndDaoCut,
                    vaultGuardians: address(this),
                    weth: address(i_weth),
                    //written 为什么需要USDC而不需要link
                    //e 确实不需要，因为我们传给ERC4626的资产为 token 在此为link，只不过名字搞错了
                    usdc: address(i_tokenOne)
                })
            );
        } else {
            revert VaultGuardiansBase__NotApprovedToken(address(token));
        }
        return _becomeTokenGuardian(token, tokenVault);
    }

    /*
     * @notice allows a guardian to quit
     * @dev this will only work if they only have a WETH vault left, a guardian can't quit if they have other vaults
     * @dev they will need to approve this contract to spend their shares tokens
     * @dev this will set the vault to no longer be active, meaning users can only withdraw tokens, and no longer deposit to the vault
     * @dev tokens should also no longer be invested into the protocols
     */
    //e 退出guardian时必须要先quot other token 后 才能quit weth vault
    function quitGuardian() external onlyGuardian(i_weth) returns (uint256) {
        if (_guardianHasNonWethVaults(msg.sender)) {
            revert VaultGuardiansBase__CantQuitWethWithThisFunction();
        }
        return _quitGuardian(i_weth);
    }

    /*
     * See VaultGuardiansBase::quitGuardian()
     * The only difference here, is that this function is for non-WETH vaults
     */
    function quitGuardian(
        IERC20 token
    ) external onlyGuardian(token) returns (uint256) {
        if (token == i_weth) {
            revert VaultGuardiansBase__CantQuitWethWithThisFunction();
        }
        return _quitGuardian(token);
    }

    /**
     * @notice Allows Vault Guardians to update their allocation ratio (and thus, their strategy of investment)
     * @param token The token vault whose allocation ratio is to be updated
     * @param tokenAllocationData The new allocation data
     */
    //written 为什么vaultShares有这个函数，这里也有？只是这里的参数不一样？
    //e 这个调用后会直接call vaultShares的updateHoldingAllocation函数
    //e 即这是上层合约，vaultshares里设置了只有此合约才有权力进行调用
    function updateHoldingAllocation(
        IERC20 token,
        AllocationData memory tokenAllocationData
    ) external onlyGuardian(token) {
        emit GuardianUpdatedHoldingAllocation(msg.sender, token);
        s_guardians[msg.sender][token].updateHoldingAllocation(
            tokenAllocationData
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _quitGuardian(IERC20 token) private returns (uint256) {
        IVaultShares tokenVault = IVaultShares(s_guardians[msg.sender][token]);
        s_guardians[msg.sender][token] = IVaultShares(address(0));
        emit GaurdianRemoved(msg.sender, token);
        tokenVault.setNotActive();
        //written 这里返回的是tokenVault 份额的数量，不是i_vgToken的数量
        //e 是的，vgtoken只有在become中,这里的作用是守护者退出时要求将自己的资金也要全额取出，算出最大的股份值后进行redeem
        uint256 maxRedeemable = tokenVault.maxRedeem(msg.sender);
        uint256 numberOfAssetsReturned = tokenVault.redeem(
            maxRedeemable,
            msg.sender,
            msg.sender
        );
        return numberOfAssetsReturned;
    }

    /**
     * @notice Checks if the vault guardian is owner of vaults other than WETH vaults
     * @param guardian the vault guardian
     */
    function _guardianHasNonWethVaults(
        address guardian
    ) private view returns (bool) {
        if (address(s_guardians[guardian][i_tokenOne]) != address(0)) {
            return true;
        } else {
            return address(s_guardians[guardian][i_tokenTwo]) != address(0);
        }
    }

    // slither-disable-start reentrancy-eth
    /*
     * @notice allows a user to become a guardian
     * @notice guardians are given a VaultGuardianToken as payment
     * @param token the token that the guardian will be guarding
     * @param tokenVault the vault that the guardian will be guarding
     */
    //written 只有guardians 才有权力获得VaultGuardianToken吗？
    //e yeah
    //written TOKEN是只需要质押一方的代币就可以成为Guardian吗
    //e 是的
    function _becomeTokenGuardian(
        IERC20 token,
        VaultShares tokenVault
    ) private returns (address) {
        s_guardians[msg.sender][token] = IVaultShares(address(tokenVault));
        emit GuardianAdded(msg.sender, token);
        //written 难道说资金就是固定的这笔钱吗，万一质押者会质押超过这个数额怎么办？
        //e 不是的，这个是点击函数后，自动调用这笔钱
        //e 全文只出现过一次vgtoken的调用，即变成guadrian后，会锻造出vgtoken
        i_vgToken.mint(msg.sender, s_guardianStakePrice);
        //written 这里是否会有重入攻击
        //e我感觉所以应该很难有重入攻击，因为没有途径可以使用fallback函数
        token.safeTransferFrom(msg.sender, address(this), s_guardianStakePrice);

        //written 那为什么不直接调用质押函数，而是先转到本合约？
        //e 不可以，因为deposit是将代币从本合约中扣除，额如果你直接调用质押函数，这个becometokenguardian的综合操作就会出现问题，vaultshares不会分清这是谁发的代币
        bool succ = token.approve(address(tokenVault), s_guardianStakePrice);
        if (!succ) {
            revert VaultGuardiansBase__TransferFailed();
        }
        uint256 shares = tokenVault.deposit(s_guardianStakePrice, msg.sender);
        if (shares == 0) {
            revert VaultGuardiansBase__TransferFailed();
        }
        return address(tokenVault);
    }

    // slither-disable-end reentrancy-eth

    /*//////////////////////////////////////////////////////////////
                   INTERNAL AND PRIVATE VIEW AND PURE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Gets the vault for a given vault guardian and a given asset token
     * @param guardian the vault guardian
     * @param token the vault's underlying asset token
     */
    function getVaultFromGuardianAndToken(
        address guardian,
        IERC20 token
    ) external view returns (IVaultShares) {
        return s_guardians[guardian][token];
    }

    /**
     * @notice Checks if the given token is supported by the protocol
     * @param token the token to check for
     */
    function isApprovedToken(address token) external view returns (bool) {
        return s_isApprovedToken[token];
    }

    /**
     * @return Address of the Aave pool
     */
    function getAavePool() external view returns (address) {
        return i_aavePool;
    }

    /**
     * @return Address of the Uniswap v2 router
     */
    function getUniswapV2Router() external view returns (address) {
        return i_uniswapV2Router;
    }

    /**
     * @return Retrieves the stake price that users have to stake to become vault guardians
     */
    function getGuardianStakePrice() external view returns (uint256) {
        return s_guardianStakePrice;
    }

    /**
     * @return The ratio of the amount in vaults that goes to the vault guardians and the DAO
     */
    function getGuardianAndDaoCut() external view returns (uint256) {
        return s_guardianAndDaoCut;
    }
}
