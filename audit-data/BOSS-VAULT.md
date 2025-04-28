<!-- Your report starts here! -->

Prepared by: [PULIN]
Lead Auditors:

- ONLY MYSELF !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# Table of Contents

- [Table of Contents](#table-of-contents)
- [Disclaimer](#disclaimer)
- [Risk Classification](#risk-classification)
- [Audit Details](#audit-details)
  - [Scope](#scope)
- [Protocol Summary](#protocol-summary)
  - [Roles](#roles)
- [Executive Summary](#executive-summary)
  - [Issues Found](#issues-found)
  - [High](#high)
    - [\[H-1\] Lack of UniswapV2 slippage protection in `UniswapAdapter::_uniswapInvest` enables frontrunners to steal profits](#h-1-lack-of-uniswapv2-slippage-protection-in-uniswapadapter_uniswapinvest-enables-frontrunners-to-steal-profits)
    - [\[H-2\] `ERC4626::totalAssets` checks the balance of vault's underlying asset even when the asset is invested, resulting in incorrect values being returned](#h-2-erc4626totalassets-checks-the-balance-of-vaults-underlying-asset-even-when-the-asset-is-invested-resulting-in-incorrect-values-being-returned)
    - [\[H-3\] Guardians can infinitely mint `VaultGuardianToken`s and take over DAO, stealing DAO fees and maliciously setting parameters](#h-3-guardians-can-infinitely-mint-vaultguardiantokens-and-take-over-dao-stealing-dao-fees-and-maliciously-setting-parameters)
    - [\[H-4\] In the constructor of `vaultshares`, the liquidityToken of Uniswap is obtained by calling the getPair function of its factory contract, but it hardcodes WETH and asset.](#h-4-in-the-constructor-of-vaultshares-the-liquiditytoken-of-uniswap-is-obtained-by-calling-the-getpair-function-of-its-factory-contract-but-it-hardcodes-weth-and-asset)
    - [\[H-5\] An attacker can impersonate the receiver and take all assets of a staker at `VaultShares`.](#h-5-an-attacker-can-impersonate-the-receiver-and-take-all-assets-of-a-staker-at-vaultshares)
    - [\[H-6\] In the `addLiquidity` function of the adapter, an investment error in assets caused Uniswap to occupy an additional 25%, i.e., 37.5%, in the entire trading strategy.](#h-6-in-the-addliquidity-function-of-the-adapter-an-investment-error-in-assets-caused-uniswap-to-occupy-an-additional-25-ie-375-in-the-entire-trading-strategy)
    - [\[H-7\] The `VaultGuardianToken` has no burning function, meaning it cannot be destroyed. Even if the fund manager exits the project, they will still retain voting rights.](#h-7-the-vaultguardiantoken-has-no-burning-function-meaning-it-cannot-be-destroyed-even-if-the-fund-manager-exits-the-project-they-will-still-retain-voting-rights)
    - [\[H-8\] The `vaultshares` contract is one-time use. When a guardian exits the project, the contract is set to inactive. However, if the next fund manager wants to participate, there is no function to reactivate the contract.](#h-8-the-vaultshares-contract-is-one-time-use-when-a-guardian-exits-the-project-the-contract-is-set-to-inactive-however-if-the-next-fund-manager-wants-to-participate-there-is-no-function-to-reactivate-the-contract)
  - [Medium](#medium)
    - [\[M-1\] Potentially incorrect voting period and delay in governor may affect governance](#m-1-potentially-incorrect-voting-period-and-delay-in-governor-may-affect-governance)
  - [Low](#low)
    - [\[L-1\] Incorrect vault name and symbol](#l-1-incorrect-vault-name-and-symbol)
    - [\[L-2\] Unassigned return value when divesting AAVE funds](#l-2-unassigned-return-value-when-divesting-aave-funds)
  - [Info](#info)
    - [\[I-1\] The `IInvestableUniverseAdapter` interface has never been used.](#i-1-the-iinvestableuniverseadapter-interface-has-never-been-used)
    - [\[I-2\] The variable GUARDIAN\_FEE has never been used.](#i-2-the-variable-guardian_fee-has-never-been-used)

# Disclaimer

The YOUR_NAME_HERE team makes all effort to find as many vulnerabilities in the code in the given time period, but holds no responsibilities for the findings provided in this document. A security audit by the team is not an endorsement of the underlying business or product. The audit was time-boxed and the review of the code was solely on the security aspects of the Solidity implementation of the contracts.

# Risk Classification

|            |        | Impact |        |     |
| ---------- | ------ | ------ | ------ | --- |
|            |        | High   | Medium | Low |
|            | High   | H      | H/M    | M   |
| Likelihood | Medium | H/M    | M      | M/L |
|            | Low    | M      | M/L    | L   |

We use the [CodeHawks](https://docs.codehawks.com/hawks-auditors/how-to-evaluate-a-finding-severity) severity matrix to determine severity. See the documentation for more details.

# Audit Details

**The findings described in this document correspond the following commit hash:**

```
XXXX
```

## Scope

```
./src/
#-- abstract
|   #-- AStaticTokenData.sol
|   #-- AStaticUSDCData.sol
|   #-- AStaticWethData.sol
#-- dao
|   #-- VaultGuardianGovernor.sol
|   #-- VaultGuardianToken.sol
#-- interfaces
|   #-- IVaultData.sol
|   #-- IVaultGuardians.sol
|   #-- IVaultShares.sol
|   #-- InvestableUniverseAdapter.sol
#-- protocol
|   #-- VaultGuardians.sol
|   #-- VaultGuardiansBase.sol
|   #-- VaultShares.sol
|   #-- investableUniverseAdapters
|       #-- AaveAdapter.sol
|       #-- UniswapAdapter.sol
#-- vendor
    #-- DataTypes.sol
    #-- IPool.sol
    #-- IUniswapV2Factory.sol
    #-- IUniswapV2Router01.sol
```

# Protocol Summary

This protocol allows users to deposit certain ERC20s into an [ERC4626 vault](https://eips.ethereum.org/EIPS/eip-4626) managed by a human being, or a `vaultGuardian`. The goal of a `vaultGuardian` is to manage the vault in a way that maximizes the value of the vault for the users who have despoited money into the vault.

## Roles

There are 4 main roles associated with the system.

- _Vault Guardian DAO_: The org that takes a cut of all profits, controlled by the `VaultGuardianToken`. The DAO that controls a few variables of the protocol, including:
  - `s_guardianStakePrice`
  - `s_guardianAndDaoCut`
  - And takes a cut of the ERC20s made from the protocol
- _DAO Participants_: Holders of the `VaultGuardianToken` who vote and take profits on the protocol
- _Vault Guardians_: Strategists/hedge fund managers who have the ability to move assets in and out of the investable universe. They take a cut of revenue from the protocol.
- _Investors_: The users of the protocol. They deposit assets to gain yield from the investments of the Vault Guardians.

# Executive Summary

The Vault Guardians project takes novel approaches to work ERC-4626 into a hedge fund of sorts, but makes some large mistakes on tracking balances and profits.

## Issues Found

| Severity | Number of issues found |
| -------- | ---------------------- |
| High     | 8                      |
| Medium   | 1                      |
| Low      | 2                      |
| Info     | 2                      |
| Gas      | 0                      |
| Total    | 13                     |

## High

### [H-1] Lack of UniswapV2 slippage protection in `UniswapAdapter::_uniswapInvest` enables frontrunners to steal profits

**Description:** In `UniswapAdapter::_uniswapInvest` the protocol swaps half of an ERC20 token so that they can invest in both sides of a Uniswap pool. It calls the `swapExactTokensForTokens` function of the `UnisapV2Router01` contract , which has two input parameters to note:

```javascript
    function swapExactTokensForTokens(
        uint256 amountIn,
@>      uint256 amountOutMin,
        address[] calldata path,
        address to,
@>      uint256 deadline
    )
```

The parameter `amountOutMin` represents how much of the minimum number of tokens it expects to return.
The `deadline` parameter represents when the transaction should expire.

As seen below, the `UniswapAdapter::_uniswapInvest` function sets those parameters to `0` and `block.timestamp`:

```javascript
    uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens(
        amountOfTokenToSwap,
@>      0,
        s_pathArray,
        address(this),
@>      block.timestamp
    );
```

**Impact:** This results in either of the following happening:

- Anyone (e.g., a frontrunning bot) sees this transaction in the mempool, pulls a flashloan and swaps on Uniswap to tank the price before the swap happens, resulting in the protocol executing the swap at an unfavorable rate.
- Due to the lack of a deadline, the node who gets this transaction could hold the transaction until they are able to profit from the guaranteed swap.

**Proof of Concept:**

1. User calls `VaultShares::deposit` with a vault that has a Uniswap allocation.
   1. This calls `_uniswapInvest` for a user to invest into Uniswap, and calls the router's `swapExactTokensForTokens` function.
2. In the mempool, a malicious user could:
   1. Hold onto this transaction which makes the Uniswap swap
   2. Take a flashloan out
   3. Make a major swap on Uniswap, greatly changing the price of the assets
   4. Execute the transaction that was being held, giving the protocol as little funds back as possible due to the `amountOutMin` value set to 0.

This could potentially allow malicious MEV users and frontrunners to drain balances.

**Recommended Mitigation:**

_For the deadline issue, we recommend the following:_

DeFi is a large landscape. For protocols that have sensitive investing parameters, add a custom parameter to the `deposit` function so the Vault Guardians protocol can account for the customizations of DeFi projects that it integrates with.

In the `deposit` function, consider allowing for custom data.

```diff
- function deposit(uint256 assets, address receiver) public override(ERC4626, IERC4626) isActive returns (uint256) {
+ function deposit(uint256 assets, address receiver, bytes customData) public override(ERC4626, IERC4626) isActive returns (uint256) {
```

This way, you could add a `deadline` to the Uniswap swap, and also allow for more DeFi custom integrations.

_For the `amountOutMin` issue, we recommend one of the following:_

1. Do a price check on something like a [Chainlink price feed](https://docs.chain.link/data-feeds) before making the swap, reverting if the rate is too unfavorable.
2. Only deposit 1 side of a Uniswap pool for liquidity. Don't make the swap at all. If a pool doesn't exist or has too low liquidity for a pair of ERC20s, don't allow investment in that pool.

Note that these recommendation require significant changes to the codebase.

### [H-2] `ERC4626::totalAssets` checks the balance of vault's underlying asset even when the asset is invested, resulting in incorrect values being returned

**Description:** The `ERC4626::totalAssets` function checks the balance of the underlying asset for the vault using the `balanceOf` function.

```javascript
function totalAssets() public view virtual returns (uint256) {
    return _asset.balanceOf(address(this));
}
```

However, the assets are invested in the investable universe (Aave and Uniswap) which means this will never return the correct value of assets in the vault.

**Impact:** This breaks many functions of the `ERC4626` contract:

- `totalAssets`
- `convertToShares`
- `convertToAssets`
- `previewWithdraw`
- `withdraw`
- `deposit`

All calculations that depend on the number of assets in the protocol would be flawed, severely disrupting the protocol functionality.

**Proof of Concept:**

<details>
<summary>Code</summary>

Add the following code to the `VaultSharesTest.t.sol` file.

```javascript
    function testConstantlyWithdrawAndDepositAndRedeem() public hasGuardian {
        //user deposit
        weth.mint(mintAmount, user);
        uint256 userWethBalanceBefore = weth.balanceOf(user); //100ether
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        //user redeem
        uint256 maxShares = wethVaultShares.maxRedeem(user);

        wethVaultShares.redeem(maxShares, user, user);
        uint256 userWethBalanceAfter = weth.balanceOf(user); //52 ether
        console2.log("userWethBalanceAfter", userWethBalanceAfter);
        assert(userWethBalanceAfter < userWethBalanceBefore);

        vm.stopPrank();
    }
```

</details>

**Recommended Mitigation:** Do not use the OpenZeppelin implementation of the `ERC4626` contract. Instead, natively keep track of users total amounts sent to each protocol. Potentially have an automation tool or some incentivised mechanism to keep track of protocol's profits and losses, and take snapshots of the investable universe.

This would take a considerable re-write of the protocol.

### [H-3] Guardians can infinitely mint `VaultGuardianToken`s and take over DAO, stealing DAO fees and maliciously setting parameters

**Description:** Becoming a guardian comes with the perk of getting minted Vault Guardian Tokens (vgTokens). Whenever a guardian successfully calls `VaultGuardiansBase::becomeGuardian` or `VaultGuardiansBase::becomeTokenGuardian`, `_becomeTokenGuardian` is executed, which mints the caller `i_vgToken`.

```javascript
    function _becomeTokenGuardian(IERC20 token, VaultShares tokenVault) private returns (address) {
        s_guardians[msg.sender][token] = IVaultShares(address(tokenVault));
@>      i_vgToken.mint(msg.sender, s_guardianStakePrice);
        emit GuardianAdded(msg.sender, token);
        token.safeTransferFrom(msg.sender, address(this), s_guardianStakePrice);
        token.approve(address(tokenVault), s_guardianStakePrice);
        tokenVault.deposit(s_guardianStakePrice, msg.sender);
        return address(tokenVault);
    }
```

Guardians are also free to quit their role at any time, calling the `VaultGuardianBase::quitGuardian` function. The combination of minting vgTokens, and freely being able to quit, results in users being able to farm vgTokens at any time.

**Impact:** Assuming the token has no monetary value, the malicious guardian could accumulate tokens until they can overtake the DAO. Then, they could execute any of these functions of the `VaultGuardians` contract:

```
  "sweepErc20s(address)": "942d0ff9",
  "transferOwnership(address)": "f2fde38b",
  "updateGuardianAndDaoCut(uint256)": "9e8f72a4",
  "updateGuardianStakePrice(uint256)": "d16fe105",
```

**Proof of Concept:**

1. User becomes WETH guardian and is minted vgTokens.
2. User quits, is given back original WETH allocation.
3. User becomes WETH guardian with the same initial allocation.
4. Repeat to keep minting vgTokens indefinitely.

<details>
<summary>Code</summary>

Place the following code into `VaultGuardiansBaseTest.t.sol`

```javascript
       function testMaliciousGuardianTakeOverTheDAO() public {
        address maliciousGuardian = makeAddr("maliciousGuardian");
        weth.mint(mintAmount, maliciousGuardian);

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
```

</details>

**Recommended Mitigation:** There are a few options to fix this issue:

1. Mint vgTokens on a vesting schedule after a user becomes a guardian.
2. Burn vgTokens when a guardian quits.
3. Simply don't allocate vgTokens to guardians. Instead, mint the total supply on contract deployment.

### [H-4] In the constructor of `vaultshares`, the liquidityToken of Uniswap is obtained by calling the getPair function of its factory contract, but it hardcodes WETH and asset.

**Description:**If `wethVaultShares`, i.e., the vault created by WETH, then both parameters passed to getPair would be WETH, which would cause an error.

```javascript
    constructor(
        ConstructorData memory constructorData
    )
    {
        i_guardian = constructorData.guardian;
        i_guardianAndDaoCut = constructorData.guardianAndDaoCut;
        i_vaultGuardians = constructorData.vaultGuardians;
        s_isActive = true;
        updateHoldingAllocation(constructorData.allocationData);


        i_aaveAToken = IERC20(
            IPool(constructorData.aavePool)
                .getReserveData(address(constructorData.asset))
                .aTokenAddress
        );

        i_uniswapLiquidityToken = IERC20(
           i_uniswapFactory.getPair(
@>                address(constructorData.asset),
               address(i_weth)
            )
        );
    }
```

### [H-5] An attacker can impersonate the receiver and take all assets of a staker at `VaultShares`.

```javascript
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
    {
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }
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
```

**Impact:** The user's staked amount will be fully stolen simply by the attacker changing the receiver parameter in the implementation of redeem and withdraw.

**Proof of Concept:**

<details>
<summary>Code</summary>

Add the following code to the `VaultGuardiansBaseTest.t.sol` file.

```javascript
    function testAttakcerFrokTheReceiverToUserRedeem() public hasGuardian {
        //user deposit
        weth.mint(mintAmount, user);
        uint256 userWethBalanceBefore = weth.balanceOf(user); //100ether
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        //attacker  redeem
        uint256 maxShares = wethVaultShares.maxRedeem(user);
        wethVaultShares.redeem(maxShares, attacker, user);
        uint256 userWethBalanceAfter = weth.balanceOf(user); //0 ether
        console2.log("attacker balance after ", weth.balanceOf(attacker)); //52 ether
        console2.log("userWethBalanceAfter", userWethBalanceAfter);

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
        wethVaultShares.withdraw(maxAssets, attacker, user);
        uint256 userWethBalanceAfter = weth.balanceOf(user); //0 ether
        console2.log("attacker balance after ", weth.balanceOf(attacker)); //52 ether
        console2.log("userWethBalanceAfter", userWethBalanceAfter);

        vm.stopPrank();
    }
```

</details>

**Recommended Mitigation:**It is recommended to add a check for whether the receiver has shares before starting.

```diff
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
+       if(...){...revert}
        uint256 assets = super.redeem(shares, receiver, owner);
        return assets;
    }
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
    {
+       if(...){...revert}
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }
```

### [H-6] In the `addLiquidity` function of the adapter, an investment error in assets caused Uniswap to occupy an additional 25%, i.e., 37.5%, in the entire trading strategy.

**Description:**

```javascript
    function _uniswapInvest(IERC20 token, uint256 amount) internal {
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;

        uint256 amountOfTokenToSwap = amount / 2;

        s_pathArray = [address(token), address(counterPartyToken)];
        bool succ = token.approve(
            address(i_uniswapRouter),
            amountOfTokenToSwap
        );
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: amountOfTokenToSwap,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });
        succ = counterPartyToken.approve(address(i_uniswapRouter), amounts[1]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        succ = token.approve(
            address(i_uniswapRouter),
            amountOfTokenToSwap + amounts[0]
        );
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        (
            uint256 tokenAmount,
            uint256 counterPartyTokenAmount,
            uint256 liquidity
        ) = i_uniswapRouter.addLiquidity({
                tokenA: address(token),
                tokenB: address(counterPartyToken),
@>                amountADesired: amountOfTokenToSwap + amounts[0],
                amountBDesired: amounts[1],
                amountAMin: 0,
                amountBMin: 0,
                to: address(this),
                deadline: block.timestamp
            });
        emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
    }

```

**Impact:**If the investment strategy is Hold: 50%, Uniswap: 25%, Aave: 25%, it would result in Uniswap receiving an additional 25% of the investment. This is because amounts[0] represents a 12.5% share, so 12.5% + 12.5% + 12.5% equals 37.5%.

**Recommended Mitigation:**

```diff
  (
            uint256 tokenAmount,
            uint256 counterPartyTokenAmount,
            uint256 liquidity
        ) = i_uniswapRouter.addLiquidity({
                tokenA: address(token),
                tokenB: address(counterPartyToken),
-                amountADesired: amountOfTokenToSwap + amounts[0],
+               amountADesired: amountOfTokenToSwap ,
                amountBDesired: amounts[1],
                amountAMin: 0,
                amountBMin: 0,
                to: address(this),
                deadline: block.timestamp
            });
        emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
    }
```

### [H-7] The `VaultGuardianToken` has no burning function, meaning it cannot be destroyed. Even if the fund manager exits the project, they will still retain voting rights.

**Description:**as you can see ,there is no burning function in the `VaultGuardianToken` contract. This means that the tokens cannot be destroyed, and if the fund manager exits the project, they will still retain voting rights.

```javascript

contract VaultGuardianToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    constructor()
        ERC20("VaultGuardianToken", "VGT")
        ERC20Permit("VaultGuardianToken")
        Ownable(msg.sender)
    {}

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

```

**Impact:**Even if the fund manager exits the project, the retention of tokens means they still have equivalent voting rights, which could suppress the activity of current fund managers.

**Recommended Mitigation:**Add a burn function to the original contract and set conditions to automatically burn the VGT tokens of a VaultGuardian or significantly reduce their voting power after they exit, thereby decreasing their voting weight.

### [H-8] The `vaultshares` contract is one-time use. When a guardian exits the project, the contract is set to inactive. However, if the next fund manager wants to participate, there is no function to reactivate the contract.

**Description:**Suppose a guardian creates a USDC contract and invests according to their strategy. Once they exit, the contract is set to inactive. However, if a second guardian wants to participate, they can only create a new contract rather than investing based on the original one, significantly reducing liquidity. If users stake in the first contract and it becomes inactive, they can only redeem or withdraw and then invest in the second contract. The redundant fees and operational complexity may discourage users from continuing to participate.

**Recommended Mitigation:**It is recommended to implement measures in the VaultGuardian contract by adding a new function that allows other guardians to join an existing vaultshares contract and autonomously allocate investment strategies.

## Medium

### [M-1] Potentially incorrect voting period and delay in governor may affect governance

The `VaultGuardianGovernor` contract, based on [OpenZeppelin Contract's Governor](https://docs.openzeppelin.com/contracts/5.x/api/governance#governor), implements two functions to define the voting delay (`votingDelay`) and period (`votingPeriod`). The contract intends to define a voting delay of 1 day, and a voting period of 7 days. It does it by returning the value `1 days` from `votingDelay` and `7 days` from `votingPeriod`. In Solidity these values are translated to number of seconds.

However, the `votingPeriod` and `votingDelay` functions, by default, are expected to return number of blocks. Not the number seconds. This means that the voting period and delay will be far off what the developers intended, which could potentially affect the intended governance mechanics.

Consider updating the functions as follows:

```diff
function votingDelay() public pure override returns (uint256) {
-   return 1 days;
+   return 7200; // 1 day
}

function votingPeriod() public pure override returns (uint256) {
-   return 7 days;
+   return 50400; // 1 week
}
```

## Low

### [L-1] Incorrect vault name and symbol

When new vaults are deployed in the `VaultGuardianBase::becomeTokenGuardian` function, symbol and vault name are set incorrectly when the `token` is equal to `i_tokenTwo`. Consider modifying the function as follows, to avoid errors in off-chain clients reading these values to identify vaults.

```diff
else if (address(token) == address(i_tokenTwo)) {
    tokenVault =
    new VaultShares(IVaultShares.ConstructorData({
        asset: token,
-       vaultName: TOKEN_ONE_VAULT_NAME,
+       vaultName: TOKEN_TWO_VAULT_NAME,
-       vaultSymbol: TOKEN_ONE_VAULT_SYMBOL,
+       vaultSymbol: TOKEN_TWO_VAULT_SYMBOL,
        guardian: msg.sender,
        allocationData: allocationData,
        aavePool: i_aavePool,
        uniswapRouter: i_uniswapV2Router,
        guardianAndDaoCut: s_guardianAndDaoCut,
        vaultGuardian: address(this),
        weth: address(i_weth),
        usdc: address(i_tokenOne)
    }));
```

Also, add a new test in the `VaultGuardiansBaseTest.t.sol` file to avoid reintroducing this error, similar to what's done in the test `testBecomeTokenGuardianTokenOneName`.

### [L-2] Unassigned return value when divesting AAVE funds

The `AaveAdapter::_aaveDivest` function is intended to return the amount of assets returned by AAVE after calling its `withdraw` function. However, the code never assigns a value to the named return variable `amountOfAssetReturned`. As a result, it will always return zero.

While this return value is not being used anywhere in the code, it may cause problems in future changes. Therefore, update the `_aaveDivest` function as follows:

```diff
function _aaveDivest(IERC20 token, uint256 amount) internal returns (uint256 amountOfAssetReturned) {
-       i_aavePool.withdraw({
+       amountOfAssetReturned = i_aavePool.withdraw({
            asset: address(token),
            amount: amount,
            to: address(this)
        });
}
```

## Info

### [I-1] The `IInvestableUniverseAdapter` interface has never been used.

**Recommended Mitigation:**

```diff
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

-interface IInvestableUniverseAdapter {
-    // function invest(IERC20 token, uint256 amount) external;
-    // function divest(IERC20 token, uint256 amount) external;
}

```

### [I-2] The variable GUARDIAN_FEE has never been used.

**Recommended Mitigation:**

```diff
-   uint256 private constant GUARDIAN_FEE = 0.1 ether;

```
