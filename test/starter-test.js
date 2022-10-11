const {time, loadFixture, mine} = require('@nomicfoundation/hardhat-network-helpers');
const {ethers, network, upgrades} = require('hardhat');
const {expect} = require('chai');
require('dotenv').config();

const moveTimeForward = async (seconds) => {
  await time.increase(seconds);
};

// eslint-disable-next-line no-unused-vars
const moveBlocksForward = async (blocks) => {
  mine(blocks);
};

const toWantUnit = (num, isUSDC = false) => {
  if (isUSDC) {
    return ethers.BigNumber.from(num * 10 ** 8);
  }
  return ethers.utils.parseEther(num);
};

const treasuryAddr = '0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B';

const superAdminAddress = '0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203';
const adminAddress = '0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B';
const guardianAddress = '0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9';
const strategistAddr = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';

const strategists = [strategistAddr];
const multisigRoles = [superAdminAddress, adminAddress, guardianAddress];

const wantAddress = '0xde45F101250f2ca1c0f8adFC172576d10c12072D';
const gauge = '0x950fdbee03900487ebc3ac54daf4c988e7c02678';
const usdcAddress = '0x7F5c764cBc14f9669B88837ca1490cCa17c31607';

const wantHolderAddr = '0x79ad42161a55840D1327c39d7B47D12d6cC4c68A';

describe('Vaults', function () {
  async function deployVaultAndStrategyAndGetSigners() {
    // reset network
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: 'https://late-fragrant-rain.optimism.quiknode.pro/70171d2e7790f3af6a833f808abe5e85ed6bd881/',
          },
        },
      ],
    });

    // get signers
    const [owner, unassignedRole] = await ethers.getSigners();
    const wantHolder = await ethers.getImpersonatedSigner(wantHolderAddr);
    const strategist = await ethers.getImpersonatedSigner(strategistAddr);
    const guardian = await ethers.getImpersonatedSigner(guardianAddress);
    const admin = await ethers.getImpersonatedSigner(adminAddress);
    const superAdmin = await ethers.getImpersonatedSigner(superAdminAddress);

    // get artifacts
    const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
    const Strategy = await ethers.getContractFactory('ReaperStrategyLidoShuffle');
    const Want = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');

    // deploy contracts
    const vault = await Vault.deploy(
      wantAddress,
      `Lido Shuffle Beethoven-X Crypt`,
      'rf-bb-wstETH',
      0,
      ethers.constants.MaxUint256,
    );
    await vault.deployed();
    const strategy = await upgrades.deployProxy(
      Strategy,
      [vault.address, treasuryAddr, strategists, multisigRoles, wantAddress, gauge],
      {kind: 'uups'},
    );
    await strategy.deployed();
    await vault.initialize(strategy.address);
    const want = Want.attach(wantAddress);
    const usdc = Want.attach(usdcAddress);

    // // send some funds to wantHolder and strategist
    let tx = await owner.sendTransaction({
      to: wantHolderAddr,
      value: ethers.utils.parseEther('1.0'),
    });
    await tx.wait();
    tx = await owner.sendTransaction({
      to: strategistAddr,
      value: ethers.utils.parseEther('1.0'),
    });
    await tx.wait();

    // // approving LP token and vault share spend
    await want.connect(wantHolder).approve(vault.address, ethers.constants.MaxUint256);
    await want.connect(owner).approve(vault.address, ethers.constants.MaxUint256);

    return {vault, strategy, want, usdc, owner, wantHolder, strategist, guardian, admin, superAdmin, unassignedRole};
  }

  xdescribe('Deploying the vault and strategy', function () {
    it('should initiate vault with a 0 balance', async function () {
      const {vault} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const totalBalance = await vault.balance();
      const availableBalance = await vault.available();
      const pricePerFullShare = await vault.getPricePerFullShare();
      expect(totalBalance).to.equal(0);
      expect(availableBalance).to.equal(0);
      expect(pricePerFullShare).to.equal(ethers.utils.parseEther('1'));
    });
  });

  xdescribe('Access control tests', function () {
    it('unassignedRole has no privileges', async function () {
      const {strategy, unassignedRole} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      await expect(strategy.connect(unassignedRole).updateHarvestLogCadence(10)).to.be.revertedWith(
        'Unauthorized access',
      );

      await expect(strategy.connect(unassignedRole).pause()).to.be.revertedWith('Unauthorized access');

      await expect(strategy.connect(unassignedRole).unpause()).to.be.revertedWith('Unauthorized access');

      await expect(strategy.connect(unassignedRole).updateSecurityFee(0)).to.be.revertedWith('Unauthorized access');
    });

    it('strategist has right privileges', async function () {
      const {strategy, strategist} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      await expect(strategy.connect(strategist).updateHarvestLogCadence(10)).to.not.be.reverted;

      await expect(strategy.connect(strategist).pause()).to.be.revertedWith('Unauthorized access');

      await expect(strategy.connect(strategist).unpause()).to.be.revertedWith('Unauthorized access');

      await expect(strategy.connect(strategist).updateSecurityFee(0)).to.be.revertedWith('Unauthorized access');
    });

    it('guardian has right privileges', async function () {
      const {strategy, strategist, guardian} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const tx = await strategist.sendTransaction({
        to: guardianAddress,
        value: ethers.utils.parseEther('1.0'),
      });
      await tx.wait();

      await expect(strategy.connect(guardian).updateHarvestLogCadence(10)).to.not.be.reverted;

      await expect(strategy.connect(guardian).pause()).to.not.be.reverted;

      await expect(strategy.connect(guardian).unpause()).to.be.revertedWith('Unauthorized access');

      await expect(strategy.connect(guardian).updateSecurityFee(0)).to.be.revertedWith('Unauthorized access');
    });

    it('admin has right privileges', async function () {
      const {strategy, strategist, admin} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const tx = await strategist.sendTransaction({
        to: adminAddress,
        value: ethers.utils.parseEther('1.0'),
      });
      await tx.wait();

      await expect(strategy.connect(admin).updateHarvestLogCadence(10)).to.not.be.reverted;

      await expect(strategy.connect(admin).pause()).to.not.be.reverted;

      await expect(strategy.connect(admin).unpause()).to.not.be.reverted;

      await expect(strategy.connect(admin).updateSecurityFee(0)).to.be.revertedWith('Unauthorized access');
    });

    it('super-admin/owner has right privileges', async function () {
      const {strategy, strategist, superAdmin} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const tx = await strategist.sendTransaction({
        to: superAdminAddress,
        value: ethers.utils.parseEther('1.0'),
      });
      await tx.wait();

      await expect(strategy.connect(superAdmin).updateHarvestLogCadence(10)).to.not.be.reverted;

      await expect(strategy.connect(superAdmin).pause()).to.not.be.reverted;

      await expect(strategy.connect(superAdmin).unpause()).to.not.be.reverted;

      await expect(strategy.connect(superAdmin).updateSecurityFee(0)).to.not.be.reverted;
    });
  });

  describe('Vault Tests', function () {
    xit('should allow deposits and account for them correctly', async function () {
      const {vault, wantHolder} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const depositAmount = toWantUnit('0.1');
      await vault.connect(wantHolder).deposit(depositAmount);

      const newVaultBalance = await vault.balance();
      const allowedInaccuracy = depositAmount.div(200);
      expect(depositAmount).to.be.closeTo(newVaultBalance, allowedInaccuracy);
    });

    xit('should mint user their pool share', async function () {
      const {vault, want, wantHolder, owner} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const depositAmount = toWantUnit('0.1');
      await vault.connect(wantHolder).deposit(depositAmount);

      const ownerDepositAmount = toWantUnit('0.1');
      await want.connect(wantHolder).transfer(owner.address, ownerDepositAmount);
      await want.connect(owner).approve(vault.address, ethers.constants.MaxUint256);
      await vault.connect(owner).deposit(ownerDepositAmount);

      const allowedImprecision = toWantUnit('0.0001');

      const userVaultBalance = await vault.balanceOf(wantHolderAddr);
      expect(userVaultBalance).to.be.closeTo(depositAmount, allowedImprecision);
      const ownerVaultBalance = await vault.balanceOf(owner.address);
      expect(ownerVaultBalance).to.be.closeTo(ownerDepositAmount, allowedImprecision);

      await vault.connect(owner).withdrawAll();
      const ownerWantBalance = await want.balanceOf(owner.address);
      expect(ownerWantBalance).to.be.closeTo(ownerDepositAmount, allowedImprecision);
      const afterOwnerVaultBalance = await vault.balanceOf(owner.address);
      expect(afterOwnerVaultBalance).to.equal(0);
    });

    xit('should allow withdrawals', async function () {
      const {vault, want, wantHolder} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.1');
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdrawAll();
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = depositAmount.mul(securityFee).div(percentDivisor);
      const expectedBalance = userBalance.sub(withdrawFee);
      const smallDifference = expectedBalance.div(200);
      const isSmallBalanceDifference = expectedBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    xit('should allow small withdrawal', async function () {
      const {vault, want, wantHolder, owner} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.0000001');
      await vault.connect(wantHolder).deposit(depositAmount);

      const ownerDepositAmount = toWantUnit('0.1');
      await want.connect(wantHolder).transfer(owner.address, ownerDepositAmount);
      await want.connect(owner).approve(vault.address, ethers.constants.MaxUint256);
      await vault.connect(owner).deposit(ownerDepositAmount);

      await vault.connect(wantHolder).withdrawAll();
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = depositAmount.mul(securityFee).div(percentDivisor);
      const expectedBalance = userBalance.sub(withdrawFee);
      const smallDifference = expectedBalance.div(200);
      const isSmallBalanceDifference = expectedBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    xit('should handle small deposit + withdraw', async function () {
      const {vault, want, wantHolder} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.0000000000001');
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdraw(depositAmount);
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = (depositAmount * securityFee) / percentDivisor;
      const expectedBalance = userBalance.sub(withdrawFee);
      const isSmallBalanceDifference = expectedBalance.sub(userBalanceAfterWithdraw) < 200;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    xit('should be able to harvest', async function () {
      const {vault, strategy, usdc, wantHolder, owner} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      await vault.connect(wantHolder).depositAll();
      await moveTimeForward(7200);
      const readOnlyStrat = await strategy.connect(ethers.provider);
      const predictedCallerFee = await readOnlyStrat.callStatic.harvest();
      console.log(`predicted caller fee ${ethers.utils.formatEther(predictedCallerFee)}`);

      const usdcBalBefore = await usdc.balanceOf(owner.address);
      await strategy.harvest();
      const usdcBalAfter = await usdc.balanceOf(owner.address);
      const usdcBalDifference = usdcBalAfter.sub(usdcBalBefore);
      console.log(`actual caller fee ${ethers.utils.formatEther(usdcBalDifference)}`);
    });

    it('should provide yield', async function () {
      const {vault, strategy, want, wantHolder} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const timeToSkip = 3600;

      await vault.connect(wantHolder).depositAll();
      const initialVaultBalance = await vault.balance();

      await strategy.updateHarvestLogCadence(timeToSkip / 2);

      const numHarvests = 5;
      for (let i = 0; i < numHarvests; i++) {
        await moveTimeForward(timeToSkip);
        await strategy.harvest();
      }

      const finalVaultBalance = await vault.balance();
      // expect(finalVaultBalance).to.be.gt(initialVaultBalance);

      const averageAPR = await strategy.averageAPRAcrossLastNHarvests(numHarvests);
      console.log(`Average APR across ${numHarvests} harvests is ${averageAPR} basis points.`);
    });
  });

  xdescribe('Strategy', function () {
    it('should be able to pause and unpause', async function () {
      const {vault, strategy, wantHolder} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      await strategy.pause();
      const depositAmount = toWantUnit('0.1');
      await expect(vault.connect(wantHolder).deposit(depositAmount)).to.be.reverted;

      await strategy.unpause();
      await expect(vault.connect(wantHolder).deposit(depositAmount)).to.not.be.reverted;
    });

    it('should be able to panic', async function () {
      const {vault, strategy, want, wantHolder} = await loadFixture(deployVaultAndStrategyAndGetSigners);
      const depositAmount = toWantUnit('0.0007');
      await vault.connect(wantHolder).deposit(depositAmount);
      const strategyBalance = await strategy.balanceOf();
      await strategy.panic();

      const wantStratBalance = await want.balanceOf(strategy.address);
      const allowedImprecision = toWantUnit('0.000000001');
      expect(strategyBalance).to.be.closeTo(wantStratBalance, allowedImprecision);
    });
  });
});
