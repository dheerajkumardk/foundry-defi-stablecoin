// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// Have our invariants

// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view functions should never revert - evergreen invariant

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin, DSCEngine} from "../../src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from './Handler.t.sol';

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();

        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the amount of dsc minted
        uint256 totalSupplyDsc = dsc.totalSupply();

        // get the value of total deposited collateral
        uint256 wethBalance = IERC20(weth).balanceOf(address(engine));
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(address(engine));
        
        uint256 wethValue = engine.getUsdValue(weth, wethBalance);
        uint256 wbtcValue = engine.getUsdValue(wbtc, wbtcBalance);

        console.log("weth: ", weth);
        console.log("wbtc: ", wbtc);

        assert(wethValue + wbtcValue >= totalSupplyDsc);
    }

    // function invariant_callSummary() public view {
    //     handler.callSummary();
    // }
}
