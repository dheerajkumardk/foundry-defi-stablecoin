// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC, HelperConfig} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin, DSCEngine} from "../../src/DSCEngine.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    uint256 public constant STARTING_TOKEN_BALANCE = 15 ether;
    uint256 public constant COLLATERAL_AMOUNT = 7 ether;
    uint256 public amountToMint = 7000e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(alice, STARTING_TOKEN_BALANCE);
        ERC20Mock(wbtc).mint(alice, STARTING_TOKEN_BALANCE);
    }

    /* Constructor Tests */
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIftokenLengthDoesntMatchPriceFeeds() external {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*/////////////////////////////////
            Price Tests
    /////////////////////////////////*/
    function testGetUsdValue() external {
        // 15 eth * 2000/ETH = 30,000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() external {
        uint256 usdAmount = 100 ether;
        // 1 ETH = 2000 USD
        // 100 USD = (1/2000) * 100 ETH = 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    /*/// DepositCollateral Tests /// */

    function testRevertsIfCollateralZero() external {
        vm.startPrank(alice);
        ERC20Mock(weth).approveInternal(msg.sender, address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert();
        engine.depositCollateral(weth, 10);
        vm.stopPrank();
    }

    function testRevertsWithUnauthorizedCollateralToken() external {
        ERC20Mock randomToken = new ERC20Mock("Random Token", "RT", msg.sender, STARTING_TOKEN_BALANCE);

        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector);
        engine.depositCollateral(address(randomToken), COLLATERAL_AMOUNT);
    }

    modifier depositedCollateral() {
        vm.startPrank(alice);
        ERC20Mock(weth).approveInternal(alice, address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() external depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    function testGetAccountCollateralValue() external depositedCollateral {
        // let's deposit wbtc also
        vm.startPrank(alice);
        ERC20Mock(wbtc).approveInternal(alice, address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wbtc, COLLATERAL_AMOUNT);
        vm.stopPrank();

        // both weth and wbtc deposited
        // 7 ETH deposited - @2000/ETH - 14,000$$
        // 7 BTC deposited - @1000/BTC - 7000 $$
        uint256 expectedCollateralValue = 21000e18;
        uint256 actualCollateralValue = engine.getAccountCollateralValue(alice);

        assertEq(expectedCollateralValue, actualCollateralValue);
    }

    modifier collateralDepositedAndDscMinted() {
        uint256 amountToMint = 7000e18;

        vm.startPrank(alice);
        ERC20Mock(weth).approveInternal(alice, address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, amountToMint);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndMintDsc() external collateralDepositedAndDscMinted {
        uint256 userDscBalance = dsc.balanceOf(alice);
        assertEq(userDscBalance, amountToMint);
    }

    /* ///// Testing Minting DSC ////// */
    function testMintDscUnderCollateralizedFails() external depositedCollateral {
        // 7 ether collateral value - can mint DSC worth max 3.5 ether
        uint256 collateralValue = engine.getAccountCollateralValue(alice);
        console.log(collateralValue);

        // 7 ether == 14,000 USD - can mint max 7000 DSC
        uint256 amountDscToMint = (collateralValue / 2) + 1e18;
        uint256 expectedHealthFactor = 999857163262391086;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountDscToMint);
    }

    function testMintDscOverCollateralizedWorks() external depositedCollateral {
        // 7 ether collateral value - can mint DSC worth max 3.5 ether
        uint256 collateralValue = engine.getAccountCollateralValue(alice);
        console.log(collateralValue);

        // 7 ether == 14,000 USD - can mint max 7000 DSC
        uint256 expectedHealthFactor = 1e18;

        vm.prank(alice);
        engine.mintDsc(amountToMint);

        // assert
        assertEq(engine.getHealthFactor(alice), expectedHealthFactor);
        (uint256 actualDscMinted,) = engine.getAccountInformation(alice);
        assertEq(actualDscMinted, amountToMint);
    }

    /*/////////// Testing Burn DSC ///////*/

    function testBurnDscWithoutMintingFails() external {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughDscMinted.selector);
        engine.burnDSC(amountToMint);
    }

    function testBurnDscWorks() external collateralDepositedAndDscMinted {
        vm.startPrank(alice);

        // approval for DSC to DSCEngine
        dsc.approve(address(engine), amountToMint);
        engine.burnDSC(amountToMint);
        vm.stopPrank();

        assertEq(engine.getAmountDscMinted(alice), 0);
    }

    /*//// Redeem Collateral Tests //// */
    function testRedeemCollateralWorksIfNoDSCMinted() external depositedCollateral {
        uint256 startingWethBalance = ERC20Mock(weth).balanceOf(alice);
        uint256 collateralDeposited = engine.getAmountOfCollateralDeposited(alice, weth);

        vm.startPrank(alice);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();

        uint256 endingWethBalance = ERC20Mock(weth).balanceOf(alice);

        assertEq(startingWethBalance + collateralDeposited, endingWethBalance);
        assertEq(engine.getAmountOfCollateralDeposited(alice, weth), 0);
    }

    function testRedeemCollateralFailsIfBreaksHealthFactor() external collateralDepositedAndDscMinted {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
    }

    function testRedeemCollateralAndBurnDSC() external collateralDepositedAndDscMinted {
        vm.startPrank(alice);
        dsc.approve(address(engine), amountToMint);
        engine.redeemCollateralForDSC(weth, COLLATERAL_AMOUNT, amountToMint);
        vm.stopPrank();

        uint256 expectedCollateral = 0;
        uint256 expectedDsc = 0;

        // assert
        assertEq(expectedCollateral, engine.getAmountOfCollateralDeposited(alice, weth));
        assertEq(expectedDsc, engine.getAmountDscMinted(alice));
    }

    /*///////  Liquidate Tests  ///////*/
    function testLiquidateRevertsIfHealthFactorOk() external depositedCollateral collateralDepositedAndDscMinted {
        vm.prank(address(engine));
        dsc.mint(bob, STARTING_TOKEN_BALANCE);

        vm.prank(bob);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, alice, amountToMint);
    }

    function testLiquidateRevertsIfHealthFactorNotImproved() external collateralDepositedAndDscMinted {
        vm.prank(address(engine));
        dsc.mint(bob, STARTING_TOKEN_BALANCE);

        vm.startPrank(bob);
        dsc.approve(address(engine), 1);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        engine.liquidate(weth, alice, 1);
        vm.stopPrank();
    }

    function testLiquidateWorks() external collateralDepositedAndDscMinted {
        vm.prank(address(engine));
        dsc.mint(bob, amountToMint);

        uint256 debtToCover = 2000e18;
        vm.startPrank(bob);
        dsc.approve(address(engine), debtToCover);

        engine.liquidate(weth, alice, debtToCover);
        vm.stopPrank();
    }
}
// 1,000,000,000,000,000,000
// 7,000,000,000,000,000,000
// 7000,000,000,000,000,000,000
// 3,000,000,000,000,000,000
