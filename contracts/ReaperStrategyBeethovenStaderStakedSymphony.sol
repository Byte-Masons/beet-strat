// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv2.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IBasePool.sol";
import "./interfaces/IBeetVault.sol";
import "./interfaces/ILinearPool.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/ISDRewarder.sol";
import "./interfaces/IBaseWeightedPool.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @dev LP compounding strategy for the Stader Staked Symphony Beethoven-X pool.
 */
contract ReaperStrategyBeethovenStaderStakedSymphony is ReaperBaseStrategyv2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant BEET_VAULT = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    address public constant MASTER_CHEF = address(0x8166994d9ebBe5829EC86Bd81258149B87faCfd3);
    address public constant SPOOKY_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for charging fees.
     * {USDC} - Used for liquidity routing and swapping in to the want token.
     * {sFTMx} - One of the pool tokens, used to join pool.
     * {BEETS} - Reward token for depositing LP into MasterChef. 
     * {SD} - Secondary reward token for depositing LP into MasterChef.
     * {BB_YV_USDC} - Intermediate pool used for liquidity routing to join pool.
     * {BB_YV_USD} - Underlying used to join pool.
     * {want} - LP token for the Beethoven-x pool.
     * {underlyings} - Array of IAsset type to represent the underlying tokens of the pool.
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant USDC = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    address public constant sFTMx = address(0xd7028092c830b5C8FcE061Af2E593413EbbC1fc1);
    address public constant BEETS = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e);
    address public constant SD = address(0x412a13C109aC30f0dB80AD3Bd1DeFd5D0A6c0Ac6);
    address public constant BB_YV_USDC = address(0x3B998BA87b11a1c5BC1770dE9793B17A0dA61561);
    address public constant BB_YV_USD = address(0x5ddb92A5340FD0eaD3987D3661AfcD6104c3b757);
    address public constant want = address(0x592fa9F9d58065096f2B7838709C116957D7B5CF);
    IAsset[] underlyings;
    
    // pools used to swap tokens
    bytes32 public constant WFTM_BEETS_POOL = 0xcde5a11a4acb4ee4c805352cec57e236bdbc3837000200000000000000000019;
    bytes32 public constant USDC_BEETS_POOL = 0x03c6b3f09d2504606936b1a4decefad204687890000200000000000000000015;
    bytes32 public constant WFTM_USDC_POOL = 0xcdf68a4d525ba2e90fe959c74330430a5a6b8226000200000000000000000008;
    bytes32 public constant SD_USDC_SFTMX_POOL = 0x0b372f3a9039d02b87434d5c1297060c1ee4d5ff00010000000000000000042f;

    /**
     * @dev Strategy variables
     * {mcPoolId} - ID of MasterChef pool in which to deposit LP tokens
     * {beetsPoolId} - bytes32 ID of the Beethoven-X pool corresponding to {want}
     */
    uint256 public constant mcPoolId = 0;
    bytes32 public constant beetsPoolId = 0x592fa9f9d58065096f2b7838709c116957d7b5cf00020000000000000000043c;
    uint256 public sftmxPosition;
    uint256 public boostedUSDPosition;

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);

        (IERC20Upgradeable[] memory tokens, , ) = IBeetVault(BEET_VAULT).getPoolTokens(beetsPoolId);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == sFTMx) {
                sftmxPosition = i;
            } else if (address(tokens[i]) == BB_YV_USDC) {
                boostedUSDPosition = i;
            }

            underlyings.push(IAsset(address(tokens[i])));
        }
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            // IERC20Upgradeable(want).safeIncreaseAllowance(MASTER_CHEF, wantBalance);
            // IMasterChef(MASTER_CHEF).deposit(mcPoolId, wantBalance, address(this));
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            // IMasterChef(MASTER_CHEF).withdrawAndHarvest(mcPoolId, _amount - wantBal, address(this));
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. It claims rewards from the masterChef.
     *      2. It charges the system fees to simplify the split.
     *      3. It swaps {BEETS} and {SD} for {want}.
     *      4. It deposits the new {want} tokens into the masterchef.
     */
    function _harvestCore() internal override {
        _claimRewards();
        _swapRewardsAndChargeFees();
        _addLiquidity();
        deposit();
    }

    function _claimRewards() internal {
        // IMasterChef(MASTER_CHEF).harvest(mcPoolId, address(this));
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _swapRewardsAndChargeFees() internal {
        _swap(SD, USDC, IERC20Upgradeable(SD).balanceOf(address(this))  * totalFee / PERCENT_DIVISOR, SD_USDC_SFTMX_POOL, true);
        _swap(USDC, WFTM, IERC20Upgradeable(USDC).balanceOf(address(this)), WFTM_USDC_POOL, true);

        _swap(BEETS, WFTM, IERC20Upgradeable(BEETS).balanceOf(address(this))  * totalFee / PERCENT_DIVISOR,WFTM_BEETS_POOL, true);

        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmBalance = wftm.balanceOf(address(this));

        if (wftmBalance != 0) {
            uint256 callFeeToUser = (wftmBalance * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmBalance * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function.
     *      Converts {BEETS} and {SD} rewards to {sFTMx} and {BB_YV_USD}
     *      which are then used to join the pool.
     */
    function _addLiquidity() internal {
        _swap(SD, sFTMx, IERC20Upgradeable(SD).balanceOf(address(this)), SD_USDC_SFTMX_POOL, true);
        _swap(BEETS, USDC, IERC20Upgradeable(BEETS).balanceOf(address(this)), USDC_BEETS_POOL, true);
        _swap(USDC, BB_YV_USDC, IERC20Upgradeable(USDC).balanceOf(address(this)), ILinearPool(BB_YV_USDC).getPoolId(), true);
        _swap(BB_YV_USDC, BB_YV_USD, IERC20Upgradeable(BB_YV_USDC).balanceOf(address(this)), ILinearPool(BB_YV_USD).getPoolId(), false);
        _joinPool();
    }

    /**
     * @dev Core harvest function. Joins {beetsPoolId} using {sFTMx} and {BB_YV_USD} balance;
     */
    function _joinPool() internal {
        uint256 sftmxBal = IERC20Upgradeable(sFTMx).balanceOf(address(this));
        uint256 boostedUsdBal = IERC20Upgradeable(BB_YV_USD).balanceOf(address(this));
        if (sftmxBal == 0 && boostedUsdBal == 0) {
            return;
        }

        IBaseWeightedPool.JoinKind joinKind = IBaseWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[sftmxPosition] = sftmxBal;
        amountsIn[boostedUSDPosition] = boostedUsdBal;
        uint256 minAmountOut = 1;
        bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

        IBeetVault.JoinPoolRequest memory request;
        request.assets = underlyings;
        request.maxAmountsIn = amountsIn;
        request.userData = userData;
        request.fromInternalBalance = false;

        IERC20Upgradeable(sFTMx).safeIncreaseAllowance(BEET_VAULT, sftmxBal);
        IBeetVault(BEET_VAULT).joinPool(beetsPoolId, address(this), address(this), request);
    }

    /**
     * @dev Core harvest function. Swaps {_amount} of {_from} to {_to} using {_poolId}.
     *      Prior to requesting the swap, allowance is increased iff {_shouldIncreaseAllowance}
     *      is true. This needs to false for the linear pool since they already have max allowance
     *      for {BEET_VAULT}.
     */
    function _swap(
        address _from,
        address _to,
        uint256 _amount,
        bytes32 _poolId,
        bool _shouldIncreaseAllowance
    ) internal {
        if (_from == _to || _amount == 0) {
            return;
        }

        IBeetVault.SingleSwap memory singleSwap;
        singleSwap.poolId = _poolId;
        singleSwap.kind = IBeetVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(_from);
        singleSwap.assetOut = IAsset(_to);
        singleSwap.amount = _amount;
        singleSwap.userData = abi.encode(0);

        IBeetVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        if (_shouldIncreaseAllowance) {
            IERC20Upgradeable(_from).safeIncreaseAllowance(BEET_VAULT, _amount);
        }
        IBeetVault(BEET_VAULT).swap(singleSwap, funds, 1, block.timestamp);
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        (uint256 amount, ) = IMasterChef(MASTER_CHEF).userInfo(mcPoolId, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        IMasterChef masterChef = IMasterChef(MASTER_CHEF);
        uint256 pendingReward = masterChef.pendingBeets(mcPoolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(BEETS).balanceOf(address(this));

        if (totalRewards != 0) {
            // use SPOOKY_ROUTER here since IBeetVault doesn't have a view query function
            address[] memory beetsToWftmPath = new address[](2);
            beetsToWftmPath[0] = BEETS;
            beetsToWftmPath[1] = WFTM;
            profit += IUniswapV2Router01(SPOOKY_ROUTER).getAmountsOut(totalRewards, beetsToWftmPath)[1];
        }

        ISDRewarder rewarder = ISDRewarder(masterChef.rewarder(mcPoolId));
        pendingReward = rewarder.pendingToken(mcPoolId, address(this));
        totalRewards = pendingReward + IERC20Upgradeable(SD).balanceOf(address(this));
        if (totalRewards != 0) {
            address[] memory sdToWftmPath = new address[](3);
            sdToWftmPath[0] = SD;
            sdToWftmPath[1] = USDC;
            sdToWftmPath[2] = WFTM;
            profit += IUniswapV2Router01(SPOOKY_ROUTER).getAmountsOut(totalRewards, sdToWftmPath)[1];
        }

        profit += IERC20Upgradeable(WFTM).balanceOf(address(this));

        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        _harvestCore();
        (uint256 poolBal, ) = IMasterChef(MASTER_CHEF).userInfo(mcPoolId, address(this));
        // IMasterChef(MASTER_CHEF).withdrawAndHarvest(mcPoolId, poolBal, address(this));

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
        }
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        // IMasterChef(MASTER_CHEF).emergencyWithdraw(mcPoolId, address(this));
    }
}
