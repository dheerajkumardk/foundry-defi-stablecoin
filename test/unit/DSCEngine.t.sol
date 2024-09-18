// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC, HelperConfig} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin, DSCEngine} from "../../src/DSCEngine.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address public alice = makeAddr("alice");
    uint256 public constant STARTING_TOKEN_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_AMOUNT = 7 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(alice, STARTING_TOKEN_BALANCE);
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

    /*/// DepositCollateral Tests /// */
    function testRevertsIfCollateralZero() external {
        vm.startPrank(alice);
        ERC20Mock(weth).approveInternal(msg.sender, address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert();
        engine.depositCollateral(weth, 10);
        vm.stopPrank();
    }
}
