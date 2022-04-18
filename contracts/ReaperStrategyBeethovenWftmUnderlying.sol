// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv1_1.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IBasePool.sol";
import "./interfaces/IBaseWeightedPool.sol";
import "./interfaces/IBeetVault.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/ITimeBasedMasterChefRewarder.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev LP compounding strategy for Beethoven-X pools that have WFTM as one of the tokens.
 */
contract ReaperStrategyBeethovenWftmUnderlying is ReaperBaseStrategyv1_1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant BEET_VAULT = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    address public constant MASTER_CHEF = address(0x8166994d9ebBe5829EC86Bd81258149B87faCfd3);
    address public constant SPOOKY_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant SPIRIT_ROUTER = address(0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {BEETS} - Reward token for depositing LP into MasterChef.
     * {CRE8R} - Reward token and also underlying used to join pool.
     * {want} - LP token for the Beethoven-x pool.
     * {underlyings} - Array of IAsset type to represent the underlying tokens of the pool.
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant BEETS = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e);
    address public constant CRE8R = address(0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0);
    address public want;
    IAsset[] underlyings;

    // pools used to swap tokens
    bytes32 public constant WFTM_BEETS_POOL = 0xcde5a11a4acb4ee4c805352cec57e236bdbc3837000200000000000000000019;

    /**
     * @dev Strategy variables
     * {mcPoolId} - ID of MasterChef pool in which to deposit LP tokens
     * {beetsPoolId} - bytes32 ID of the Beethoven-X pool corresponding to {want}
     * {wftmPosition} - Index of {WFTM} in the Beethoven-X pool
     * {cre8rPosition} - Index of {CRE8R} in the Beethoven-X pool
     */
    uint256 public mcPoolId;
    bytes32 public beetsPoolId;
    uint256 public wftmPosition;
    uint256 public cre8rPosition;

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _want,
        uint256 _mcPoolId
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        want = _want;
        mcPoolId = _mcPoolId;
        beetsPoolId = IBasePool(want).getPoolId();

        (IERC20Upgradeable[] memory tokens, , ) = IBeetVault(BEET_VAULT).getPoolTokens(beetsPoolId);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == WFTM) {
                wftmPosition = i;
            } else if (address(tokens[i]) == CRE8R) {
                cre8rPosition = i;
            }

            underlyings.push(IAsset(address(tokens[i])));
        }

        _giveAllowances();
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IMasterChef(MASTER_CHEF).deposit(mcPoolId, wantBalance, address(this));
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IMasterChef(MASTER_CHEF).withdrawAndHarvest(mcPoolId, _amount - wantBal, address(this));
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {BEETS} and {CRE8R} from the {MASTER_CHEF}.
     *      2. Swaps {BEETS} and {CRE8R} to {WFTM} and charges fees.
     *      3. Joins {beetsPoolId} using remaining {WFTM} and {CRE8R}.
     *      4. Deposits.
     */
    function _harvestCore() internal override {
        _claimRewards();
        _swapRewardsAndChargeFees();
        _joinPool();
        deposit();
    }

    function _claimRewards() internal {
        IMasterChef(MASTER_CHEF).harvest(mcPoolId, address(this));
    }

    /**
     * @dev Core harvest function. Swaps {BEETS} and {CRE8R} to {WFTM}.
     */
    function _swapRewardsAndChargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 cre8rBalance = IERC20Upgradeable(CRE8R).balanceOf(address(this));
        uint256 wftmFee = 0;
        uint256 initialWftmBalance = wftm.balanceOf(address(this));
        _swap(CRE8R, WFTM, cre8rBalance * totalFee / PERCENT_DIVISOR, beetsPoolId);
        wftmFee = wftm.balanceOf(address(this)) - initialWftmBalance;
        uint256 beetsBalance = IERC20Upgradeable(BEETS).balanceOf(address(this));
        initialWftmBalance = wftm.balanceOf(address(this));
        _swap(BEETS, WFTM, beetsBalance, WFTM_BEETS_POOL);
        wftmFee += (wftm.balanceOf(address(this)) - initialWftmBalance) * totalFee / PERCENT_DIVISOR;

        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Swaps {_amount} of {_from} to {_to} using {_poolId}.
     */
    function _swap(
        address _from,
        address _to,
        uint256 _amount,
        bytes32 _poolId
    ) internal {
        if (_from == _to || _amount < 100) {
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

        IERC20Upgradeable(_from).safeIncreaseAllowance(BEET_VAULT, _amount);
        IBeetVault(BEET_VAULT).swap(singleSwap, funds, 1, block.timestamp);
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = (wftm.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Joins {beetsPoolId} using {WFTM} balance;
     */
    function _joinPool() internal {
        uint256 wftmBalance = IERC20Upgradeable(WFTM).balanceOf(address(this));
        uint256 cre8rBalance = IERC20Upgradeable(CRE8R).balanceOf(address(this));
        if (wftmBalance == 0 && cre8rBalance == 0) {
            return;
        }

        IBaseWeightedPool.JoinKind joinKind = IBaseWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;
        uint256[] memory amountsIn = new uint256[](underlyings.length);
        amountsIn[wftmPosition] = wftmBalance;
        amountsIn[cre8rPosition] = cre8rBalance;
        uint256 minAmountOut = 1;
        bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

        IBeetVault.JoinPoolRequest memory request;
        request.assets = underlyings;
        request.maxAmountsIn = amountsIn;
        request.userData = userData;
        request.fromInternalBalance = false;

        IERC20Upgradeable(WFTM).safeIncreaseAllowance(BEET_VAULT, wftmBalance);
        IERC20Upgradeable(CRE8R).safeIncreaseAllowance(BEET_VAULT, cre8rBalance);
        IBeetVault(BEET_VAULT).joinPool(beetsPoolId, address(this), address(this), request);
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
        ITimeBasedMasterChefRewarder rewarder = ITimeBasedMasterChefRewarder(masterChef.rewarder(mcPoolId));

        uint256 pendingReward = masterChef.pendingBeets(mcPoolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(BEETS).balanceOf(address(this));

        if (totalRewards != 0) {
            // use SPOOKY_ROUTER here since IBeetVault doesn't have a view query function
            address[] memory beetsToWftmPath = new address[](2);
            beetsToWftmPath[0] = BEETS;
            beetsToWftmPath[1] = WFTM;
            profit += IUniswapV2Router01(SPOOKY_ROUTER).getAmountsOut(totalRewards, beetsToWftmPath)[1];
        }

        // {CRE8R)} reward
        pendingReward = rewarder.pendingToken(mcPoolId, address(this));
        totalRewards = pendingReward + IERC20Upgradeable(CRE8R).balanceOf(address(this));
        if (totalRewards != 0) {
            address[] memory cre8rToWftm = new address[](2);
            cre8rToWftm[0] = CRE8R;
            cre8rToWftm[1] = WFTM;
            profit += IUniswapV2Router01(SPIRIT_ROUTER).getAmountsOut(totalRewards, cre8rToWftm)[1];
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
        IMasterChef(MASTER_CHEF).harvest(mcPoolId, address(this));
        _swapRewardsAndChargeFees();
        _joinPool();

        (uint256 poolBal, ) = IMasterChef(MASTER_CHEF).userInfo(mcPoolId, address(this));
        if (poolBal != 0) {
            IMasterChef(MASTER_CHEF).withdrawAndHarvest(mcPoolId, poolBal, address(this));
        }

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
        }
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChef(MASTER_CHEF).emergencyWithdraw(mcPoolId, address(this));
    }

    /**
     * @dev Gives all the necessary allowances to:
     *      - deposit {want} into {MASTER_CHEF}
     */
    function _giveAllowances() internal override {
        IERC20Upgradeable(want).safeApprove(MASTER_CHEF, 0);
        IERC20Upgradeable(want).safeApprove(MASTER_CHEF, type(uint256).max);
    }

    /**
     * @dev Removes all the allowances that were given above.
     */
    function _removeAllowances() internal override {
        IERC20Upgradeable(want).safeApprove(MASTER_CHEF, 0);
    }
}
