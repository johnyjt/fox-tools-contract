// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ERC20Mock} from "../src/ERC20Mock.sol";
import {DEMOToken} from "../src/DEMOToken.sol";
import {PancakeV2TradeV1} from "../src/PancakeV2TradeV1.sol";
import {IPancakeRouter01} from "../src/interfaces/IPancakeRouter01.sol";

// https://rpc.tenderly.co/fork/cb95318c-d7c8-4eb8-844c-af561053f859
//forge script script/PancakeV2TradeV1Pro.s.sol:PancakeV2TradeV1ProTest --rpc-url https://rpc.tenderly.co/fork/70d23449-2d7c-4fac-89dd-6adb0778b4cf  --broadcast  --slow   -vvvv
// forge script script/PancakeV2TradeV1Pro.s.sol:PancakeV2TradeV1ProTest --rpc-url https://data-seed-prebsc-1-s3.bnbchain.org:8545  --broadcast  --slow   -vvvv
contract PancakeV2TradeV1ProTest is Script {
    address sender; //0x53eB7B6EF76d3a5b28F845EFf76280cF98DD7eeF
    //pro
    address router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    //test
    // address factory = 0x6725F303b657a9451d8BA641348b6761A6CC7a17;
    // address router = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    function run() public {
        test_trade();
    }

    function test_trade() public {
        sender = vm.addr(vm.envUint("OP_PRI_PRO"));
        vm.startBroadcast(vm.envUint("OP_PRI_PRO"));
        PancakeV2TradeV1 trade = new PancakeV2TradeV1(factory,router);
        // PancakeV2TradeV1 trade = PancakeV2TradeV1(payable(0x04F08c16aFD8Ef1bc36A426af3badA5Cf2789Cdf));

        // ERC20Mock usdt = new ERC20Mock("USDT", "USDT");
        // ERC20Mock token = new ERC20Mock("TEST", "TEST");

        // ERC20Mock usdt = ERC20Mock(0x55d398326f99059fF775485246999027B3197955);
        // ERC20Mock token = ERC20Mock(0x2413d55Ea3c28ff62aD0443c76c2c7DdA00F4491);

        // ERC20Mock usdt = ERC20Mock(0x55d398326f99059fF775485246999027B3197955);

        // DEMOToken token = new DEMOToken("BURNABLE", "BURN",1e28);
        // DEMOToken token = DEMOToken(0x90b2fDb5D5c5e4cA191c6CDd75cA0805Ca39167A);
        // trade.getPair(address(usdt), address(token));


        // token.setBindValid(1);
        // token.setRewardPool(sender);
        // token.setPair(0x8435235956C59D72043854428B6C910E3D55c822);
        // token.setPair(address(0));

        trade.setMaker(sender);

        // token.approve(address(router), type(uint256).max);
        // usdt.approve(address(router), type(uint256).max);

        // IPancakeRouter01(router).addLiquidity(
        //     address(token), address(usdt), 1e24, 1e24, 0, 0, sender, type(uint256).max
        // );
        // usdt.approve(address(trade), type(uint256).max);

        // address[] memory path = new address[](2);
        // path[0] = address(usdt);
        // path[1] = address(token);

        // address[] memory tos = new address[](10);
        // uint256[] memory amountIns = new uint256[](10);
        // for (uint256 i = 0; i < 10; i++) {
        //     tos[i] = trade.getBotAddr(sender, uint16(i));
        //     amountIns[i] = 1e19;
        // }
        // trade.swapExactTokensForTokensFromTreasury(sender, type(uint256).max, path, tos, amountIns, 0);

        // path[0] = address(token);
        // path[1] = address(usdt);

        // uint16[] memory botIds = new uint16[](10);

        // for (uint256 i = 0; i < 10; i++) {
        //     botIds[i] = uint16(i);
        //     amountIns[i] = 1e18;
        // }
        // trade.swapExactTokensForTokensFromBots(sender, type(uint256).max, path, botIds, amountIns, 0);
        // trade.swapExactTokensForTokensFromBots(sender, type(uint256).max, path, botIds, amountIns, 0);
    }
}
