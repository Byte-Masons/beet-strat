// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv3.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IBasePool.sol";
import "./interfaces/IBaseWeightedPool.sol";
import "./interfaces/IBeetVault.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";


/**
 * @dev LP compounding strategy for Beethoven-X pools that have WFTM as one of the tokens.
 */
contract ReaperStrategyBeethovenFantomOfTheOperaII is ReaperBaseStrategyv3_1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant BEET_VAULT = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    address public constant MASTER_CHEF = address(0x8166994d9ebBe5829EC86Bd81258149B87faCfd3);
    address public constant SPOOKY_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    /**
     * @dev Tokens Used:
     * {USDC} - Required for fees.
     * {BEETS} - Reward token for depositing LP into MasterChef.
     * {want} - LP token for the Beethoven-x pool.
     * {underlyings} - Array of IAsset type to represent the underlying tokens of the pool.
     */
    IERC20Upgradeable public constant BEETS = IERC20Upgradeable(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e);
    IERC20Upgradeable public constant USDC = IERC20Upgradeable(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    IERC20Upgradeable public want;
    IAsset[] underlyings;

    // pools used to swap tokens
    bytes32 public constant SYMPHONY_NO10 = 0x03c6b3f09d2504606936b1a4decefad204687890000200000000000000000015; // beets usdc

    /**
     * @dev Strategy variables
     * {mcPoolId} - ID of MasterChef pool in which to deposit LP tokens
     * {beetsPoolId} - bytes32 ID of the Beethoven-X pool corresponding to {want}
     * {oathPosition} - Index of {WFTM} in the Beethoven-X pool
     */
    uint256 public mcPoolId; //99
    bytes32 public beetsPoolId;
    uint256 public usdcPosition;

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address _treasury,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _want,
        uint256 _mcPoolId
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _treasury, _strategists, _multisigRoles, _keepers);
        want = IERC20Upgradeable(_want);
        mcPoolId = _mcPoolId;
        beetsPoolId = IBasePool(address(want)).getPoolId();

        (IERC20Upgradeable[] memory tokens, , ) = IBeetVault(BEET_VAULT).getPoolTokens(beetsPoolId);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == address(USDC)) {
                usdcPosition = i;
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
            IERC20Upgradeable(want).safeIncreaseAllowance(MASTER_CHEF, wantBalance);
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
     *      1. Claims {BEETS} from the {MASTER_CHEF}.
     *      2. Swaps {BEETS} to {WFTM} using {WFTM_BEETS_POOL}.
     *      3. Claims fees for the harvest caller and treasury.
     *      4. Joins {beetsPoolId} using remaining {WFTM}.
     *      5. Deposits.
     */
    function _harvestCore() internal override returns (uint256 callerFee) {
        IMasterChef(MASTER_CHEF).harvest(mcPoolId, address(this));
        callerFee = _chargeFees();
        _joinPool();
        deposit();
    }

    /**
     * @dev Core harvest function. Swaps {BEETS} to {WETH} using {DANTE_SYMPHONY}.
     */
    function _swapBeetsToUSDC() internal {
        uint256 beetsBal = IERC20Upgradeable(BEETS).balanceOf(address(this));
        if (beetsBal == 0) {
            return;
        }

        IBeetVault.SingleSwap memory singleSwap;
        singleSwap.poolId = SYMPHONY_NO10;
        singleSwap.kind = IBeetVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(address(BEETS));
        singleSwap.assetOut = IAsset(address(USDC));
        singleSwap.amount = beetsBal;
        singleSwap.userData = abi.encode(0);

        IBeetVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        IERC20Upgradeable(BEETS).safeIncreaseAllowance(BEET_VAULT, beetsBal);
        IBeetVault(BEET_VAULT).swap(singleSwap, funds, 1, block.timestamp);
    }


    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WETH gained from reward
     */
    function _chargeFees() internal returns (uint256 usdcFee) {
        uint256 usdcBalBefore = USDC.balanceOf(address(this));
        uint256 BeetsBal = BEETS.balanceOf(address(this));

        if (BeetsBal != 0) {
            _swapBeetsToUSDC();
            usdcFee = ((USDC.balanceOf(address(this)) - usdcBalBefore) * totalFee) / PERCENT_DIVISOR;
            USDC.safeTransfer(treasury, usdcFee);
        }
    }

    /**
     * @dev Core harvest function. Joins {beetsPoolId} using {WETH} balance;
     */
    function _joinPool() internal {
        uint256 usdcBal = USDC.balanceOf(address(this));
        if (usdcBal == 0) {
            return;
        }

        IBaseWeightedPool.JoinKind joinKind = IBaseWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;
        uint256[] memory amountsIn = new uint256[](underlyings.length);
        amountsIn[usdcPosition] = usdcBal;
        uint256 minAmountOut = 1;
        bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

        IBeetVault.JoinPoolRequest memory request;
        request.assets = underlyings;
        request.maxAmountsIn = amountsIn;
        request.userData = userData;
        request.fromInternalBalance = false;

        USDC.safeIncreaseAllowance(BEET_VAULT, usdcBal);
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
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChef(MASTER_CHEF).emergencyWithdraw(mcPoolId, address(this));
    }
}