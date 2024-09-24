// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from '../mocks/ERC20Mock.sol';
import {MockV3Aggregator} from '../mocks/MockV3Aggregator.sol';

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint96 public constant MAX_DEPOSIT = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("hola");
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        collateral.mint(msg.sender, amountCollateral);
        console.log("handler tokens: ", address(collateral));

        collateral.approveInternal(msg.sender, address(engine), amountCollateral);
        vm.prank(msg.sender);
        engine.depositCollateral(address(collateral), amountCollateral);
    }

    /* Aggregator */
    function updateCollateralPrice(uint128, /* newPrice */ uint256 collateralSeed) public {
        int256 newPrice = 0;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(engine.getPriceFeedAddress(address(collateral)));

        priceFeed.updateAnswer(newPrice);
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function callSummary() external view {
        console.log("Weth total deposited", weth.balanceOf(address(engine)));
        console.log("Wbtc total deposited", wbtc.balanceOf(address(engine)));
        console.log("Total supply of DSC", dsc.totalSupply());
    }
}
