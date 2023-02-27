// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/ReaperStrategyBeethovenFTMOII.sol";
import "contracts/ReaperVaultv1_4.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
//import "oz-contracts/token/ERC20/ERC20.sol";

contract ReaperStrategyBeethovenFantomOfTheOperaIITest is Test {
    // Fork Identifier
    uint256 public fantomFork;

    // Registry
    address public treasuryAddr = 0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b;

    address public superAdminAddress = 0x04C710a1E8a738CDf7cAD3a52Ba77A784C35d8CE;
    address public adminAddress = 0x539eF36C804e4D735d8cAb69e8e441c12d4B88E0;
    address public guardianAddress = 0xf20E25f2AB644C8ecBFc992a6829478a85A98F2c;
    address public wantAddress = 0x56aD84b777ff732de69E85813DAEE1393a9FFE10;
    uint256 public pool_id = 99;
    address public wftmAddress = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public usdcAddress = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;

    address public wantHolderAddr = 0x60BC5E0440C867eEb4CbcE84bB1123fad2b262B1;
    address public strategistAddr = 0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4;

    address public owner = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

    address[] keepers = [
        0xe0268Aa6d55FfE1AA7A77587e56784e5b29004A2,
        0x34Df14D42988e4Dc622e37dc318e70429336B6c5,
        0x73C882796Ea481fe0A2B8DE499d95e60ff971663,
        0x36a63324edFc157bE22CF63A6Bf1C3B49a0E72C0,
        0x9a2AdcbFb972e0EC2946A342f46895702930064F,
        0x7B540a4D24C906E5fB3d3EcD0Bb7B1aEd3823897,
        0x8456a746e09A18F9187E5babEe6C60211CA728D1,
        0x55a078AFC2e20C8c20d1aa4420710d827Ee494d4,
        0x5241F63D0C1f2970c45234a0F5b345036117E3C2,
        0xf58d534290Ce9fc4Ea639B8b9eE238Fe83d2efA6,
        0x5318250BD0b44D1740f47a5b6BE4F7fD5042682D,
        0x33D6cB7E91C62Dd6980F16D61e0cfae082CaBFCA,
        0x51263D56ec81B5e823e34d7665A1F505C327b014,
        0x87A5AfC8cdDa71B5054C698366E97DB2F3C2BC2f
    ];

    address[] public strategists = [strategistAddr];
    address[] public multisigRoles = [superAdminAddress, adminAddress, guardianAddress];

    // Initialized during set up in initial tests
    // vault, strategy, want, wftm, owner, wantHolder, strategist, guardian, admin, superAdmin, unassignedRole
    ReaperVaultv1_4 public vault;
    string public vaultName = "TOMB-MAI Tomb Crypt";
    string public vaultSymbol = "rf-TOMB-MAI";
    uint256 public vaultFee = 0;
    uint256 public vaultTvlCap = type(uint256).max;

    ReaperStrategyBeethovenFantomOfTheOperaII public implementation;
    ERC1967Proxy public proxy;
    ReaperStrategyBeethovenFantomOfTheOperaII public wrappedProxy;

    ReaperStrategyBeethovenFantomOfTheOperaII public implementationV2;
    ReaperStrategyBeethovenFantomOfTheOperaII public implementationV3;

    ERC20 public want = ERC20(wantAddress);
    ERC20 public wftm = ERC20(wftmAddress);
    ERC20 public usdc = ERC20(usdcAddress);

    function setUp() public {
        // Forking
        fantomFork = vm.createSelectFork('https://rpc.ankr.com/fantom', 56327581);
        assertEq(vm.activeFork(), fantomFork);

        // Deploying stuff
        vault = new ReaperVaultv1_4(wantAddress, vaultName, vaultSymbol, vaultFee, vaultTvlCap);
        implementation = new ReaperStrategyBeethovenFantomOfTheOperaII();
        proxy = new ERC1967Proxy(address(implementation), "");
        wrappedProxy = ReaperStrategyBeethovenFantomOfTheOperaII(address(proxy));
        wrappedProxy.initialize(address(vault), treasuryAddr, strategists, multisigRoles, keepers, wantAddress, pool_id);
        vault.initialize(address(proxy));

        implementationV2 = new ReaperStrategyBeethovenFantomOfTheOperaII();
        implementationV3 = new ReaperStrategyBeethovenFantomOfTheOperaII();

        vm.prank(wantHolderAddr);
        want.approve(address(vault), type(uint256).max);
        vm.label(address(vault), "vault");
        vm.label(address(proxy), "strat");
        vm.label(usdcAddress, "usdc");
    }

    ///------ DEPLOYMENT ------\\\\

    function testVaultDeployedWith0Balance() public {
        uint256 totalBalance = vault.balance();
        uint256 availableBalance = vault.available();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        assertEq(totalBalance, 0);
        assertEq(availableBalance, 0);
        assertEq(pricePerFullShare, 1e18);
    }

    function testCannotUpgradeWithoutInitiatingCooldown() public {
        vm.expectRevert();
        wrappedProxy.upgradeTo(address(implementationV2));
    }

    function testCannotUpgradeBeforeTimelockPassed() public {
        wrappedProxy.initiateUpgradeCooldown();

        vm.expectRevert();
        wrappedProxy.upgradeTo(address(implementationV2));
    }

    function testCanUpgradeOnceTimelockPassed() public {
        uint256 timeToSkip = wrappedProxy.UPGRADE_TIMELOCK() + 10;
        wrappedProxy.initiateUpgradeCooldown();
        skip(timeToSkip);
        wrappedProxy.upgradeTo(address(implementationV2));
    }

    function testSuccessiveUpgradesNeedToInitiateTimelockAgain() public {
        uint256 timeToSkip = wrappedProxy.UPGRADE_TIMELOCK() + 10;
        wrappedProxy.initiateUpgradeCooldown();
        skip(timeToSkip);
        wrappedProxy.upgradeTo(address(implementationV2));

        vm.expectRevert();
        wrappedProxy.upgradeTo(address(implementationV3));

        wrappedProxy.initiateUpgradeCooldown();
        vm.expectRevert();
        wrappedProxy.upgradeTo(address(implementationV3));

        skip(timeToSkip);
        wrappedProxy.upgradeTo(address(implementationV3));
    }

    ///------ ACCESS CONTROL ------\\\

    function testUnassignedRoleCannotPassAccessControl() public {
        vm.expectRevert("Unauthorized access");
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // random address
        wrappedProxy.updateHarvestLogCadence(10);

        vm.expectRevert("Unauthorized access");
        wrappedProxy.pause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.unpause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.updateSecurityFee(0);
    }

    function testStrategistHasRightPrivileges() public {
        vm.startPrank(strategistAddr);

        wrappedProxy.updateHarvestLogCadence(10);

        vm.expectRevert("Unauthorized access");
        wrappedProxy.pause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.unpause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.updateSecurityFee(0);
    }

    function testGuardianHasRightPrivilieges() public {
        vm.startPrank(guardianAddress);

        wrappedProxy.updateHarvestLogCadence(10);

        wrappedProxy.pause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.unpause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.updateSecurityFee(0);
    }

    function testAdminHasRightPrivileges() public {
        vm.startPrank(adminAddress);

        wrappedProxy.updateHarvestLogCadence(10);

        wrappedProxy.pause();

        wrappedProxy.unpause();

        vm.expectRevert("Unauthorized access");
        wrappedProxy.updateSecurityFee(0);
    }

    function testSuperAdminOrOwnerHasRightPrivileges() public {
        vm.startPrank(superAdminAddress);

        wrappedProxy.updateHarvestLogCadence(10);

        wrappedProxy.pause();

        wrappedProxy.unpause();

        wrappedProxy.updateSecurityFee(0);
    }

    ///------ VAULT AND STRATEGY------\\\

    function testCanTakeDeposits() public {
        vm.startPrank(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 2000) / 10000;
        vault.deposit(depositAmount);

        uint256 newVaultBalance = vault.balance();
        //assertApproxEqRel(newVaultBalance, depositAmount, 0.005e18);
    }

    function testVaultCanMintUserPoolShare() public {
        vm.startPrank(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 2000) / 10000;
        vault.deposit(depositAmount);

        uint256 ownerDepositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        want.transfer(owner, ownerDepositAmount);
        vm.stopPrank();
        vm.startPrank(owner);
        want.approve(address(vault), ownerDepositAmount);
        vault.deposit(ownerDepositAmount);
        
        uint256 allowedImprecision = 1e15;

        uint256 userVaultBalance = vault.balanceOf(wantHolderAddr);
        assertApproxEqRel(userVaultBalance, depositAmount, allowedImprecision);
        uint256 ownerVaultBalance = vault.balanceOf(owner);
        assertApproxEqRel(ownerVaultBalance, ownerDepositAmount, allowedImprecision);

        vault.withdrawAll();
        uint256 ownerWantBalance = want.balanceOf(owner);
        assertApproxEqRel(ownerWantBalance, ownerDepositAmount, allowedImprecision);
        ownerVaultBalance = vault.balanceOf(owner);
        assertEq(ownerVaultBalance, 0);
    }

    function testVaultAllowsWithdrawals() public {
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);
        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testVaultAllowsSmallWithdrawal() public {
        vm.startPrank(wantHolderAddr);
        uint256 ownerDepositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;
        want.transfer(owner, ownerDepositAmount);

        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 100) / 10000;
        vault.deposit(depositAmount);

        vm.stopPrank();
        vm.startPrank(owner);
        want.approve(address(vault), type(uint256).max);
        vault.deposit(ownerDepositAmount);
        vm.stopPrank();

        vm.prank(wantHolderAddr);
        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testVaultHandlesSmallDepositAndWithdraw() public {
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 10) / 10000;
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);

        vault.withdraw(depositAmount);
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        assertEq(userBalance, userBalanceAfterWithdraw);
    }

    function testVaultTaxableAddress() public {
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        vm.prank(adminAddress);
        wrappedProxy.addToFeeOnWithdraw(wantHolderAddr);
        vm.startPrank(wantHolderAddr);
        vault.deposit(depositAmount);
        vault.withdrawAll();
        uint256 userBalanceAfterWithdraw = want.balanceOf(wantHolderAddr);

        uint256 securityFee = 10;
        uint256 percentDivisor = 10000;
        uint256 withdrawFee = (depositAmount * securityFee) / percentDivisor;
        uint256 expectedBalance = userBalance - withdrawFee;
        uint256 smallDifference = expectedBalance / 200;
        bool isSmallBalanceDifference = (expectedBalance - userBalanceAfterWithdraw) < smallDifference;
        assertEq(isSmallBalanceDifference, true);
    }

    function testCanHarvest() public {
        uint256 userBalance = want.balanceOf(wantHolderAddr);
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;

        uint256 timeToSkip = 3600;
        uint curBlock = block.number;
        vm.prank(wantHolderAddr);
        vault.deposit(userBalance);
        skip(timeToSkip);
        vm.roll(curBlock + timeToSkip);

        uint256 usdcBalBefore = usdc.balanceOf(treasuryAddr);
        vm.prank(keepers[0]);
        wrappedProxy.harvest();
        uint256 usdcBalAfter = usdc.balanceOf(treasuryAddr);
        uint256 usdcBalDiff = usdcBalAfter - usdcBalBefore;
        assertEq(usdcBalDiff > 0, true);
    }

    function testCanProvideYield() public {
        uint curBlock = block.number;
        uint256 timeToSkip = 360000;
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 1000) / 10000;

        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);
        uint256 initialVaultBalance = vault.balance();

        wrappedProxy.updateHarvestLogCadence(timeToSkip / 2);
        uint256 numHarvests = 5;

        for (uint256 i; i < numHarvests; i++) {
            curBlock += timeToSkip;
            skip(timeToSkip);
            vm.roll(curBlock);
            wrappedProxy.harvest();
        }

        uint256 finalVaultBalance = vault.balance();
        assertEq(finalVaultBalance > initialVaultBalance, true);

        int256 averageAPR = wrappedProxy.averageAPRAcrossLastNHarvests(int256(numHarvests));
        emit log_named_int("Average APR across numHarvests harvests is ", averageAPR);
    }

    function testCanPauseAndUnpauseStrategy() public {
        wrappedProxy.pause();
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        vm.prank(wantHolderAddr);
        vm.expectRevert("Pausable: paused");
        vault.deposit(depositAmount);

        wrappedProxy.unpause();
        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);
    }

    function testCanPanic() public {
        uint256 depositAmount = (want.balanceOf(wantHolderAddr) * 5000) / 10000;
        vm.prank(wantHolderAddr);
        vault.deposit(depositAmount);
        uint256 strategyBalance = wrappedProxy.balanceOf();
        wrappedProxy.panic();

        uint256 wantStratBalance = want.balanceOf(address(wrappedProxy));
        uint256 allowedImprecision = 1e9;
        assertApproxEqRel(wantStratBalance, strategyBalance, allowedImprecision);
    }
}