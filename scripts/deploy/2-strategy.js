const hre = require('hardhat');

async function main() {
  const vaultAddress = '0xD3455C05CB1c0F15596dCe5b43680D4908f64a9C';
  const want = '0xeFb0D9F51EFd52d7589A9083A6d0CA4de416c249';
  const joinErc = '0x00a35FD824c717879BF370E70AC6868b95870Dfb';//IB
  const gauge = '0x3672884a609bFBb008ad9252A544F52dF6451A03';

  const WETHUsdcPool = '0xefb0d9f51efd52d7589a9083a6d0ca4de416c24900020000000000000000002c';

  const Strategy = await ethers.getContractFactory('ReaperStrategyLennonLong');

  const treasuryAddress = '0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B';
  const paymentSplitterAddress = '0x2b394b228908fb7DAcafF5F340f1b442a39B056C';

  const strategist1 = '0x1E71AEE6081f62053123140aacC7a06021D77348';
  const strategist2 = '0x81876677843D00a7D792E1617459aC2E93202576';
  const strategist3 = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
  const strategist4 = '0x4C3490dF15edFa178333445ce568EC6D99b5d71c';

  const superAdmin = '0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203';
  const admin = '0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B';
  const guardian = '0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9';

  const strategy = await hre.upgrades.deployProxy(
    Strategy,
    [
      vaultAddress,
      [treasuryAddress, paymentSplitterAddress],
      [strategist1, strategist2, strategist3, strategist4],
      [superAdmin, admin, guardian],
      want,
      joinErc,
      gauge,
      WETHUsdcPool
    ],
    {kind: 'uups', timeout: 0},
  );

  await strategy.deployed();
  console.log('Strategy deployed to:', strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
