// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ERC20Mock} from "../src/ERC20Mock.sol";
import {PancakeV2TradeV1, ExecutorBot, ISwapRouter} from "../src/PancakeV2TradeV1.sol";
import {IPancakeRouter01} from "../src/interfaces/IPancakeRouter01.sol";

// forge script script/PancakeV2TradeV1.s.sol:PancakeV2TradeV1Test --rpc-url https://data-seed-prebsc-1-s3.bnbchain.org:8545  --broadcast  --slow   -vvvv
contract PancakeV2TradeV1Test is Script {
    address sender;
    //pro
    // address router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    // address factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    //test
    address routerv2 = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
    address routerv3 = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;

    function run() public {
        test_trade();
    }

    function test_trade() public {
        sender = vm.addr(vm.envUint("OP_PRI"));
        vm.startBroadcast(vm.envUint("OP_PRI"));
        // PancakeV2TradeV1 trade = new PancakeV2TradeV1(routerv2, routerv3);
        PancakeV2TradeV1 trade = PancakeV2TradeV1(payable(0xb0BECf5E5e17c4B941F39880eC7bFaD1cf08dd1a));
        address impl = trade.executorBotImpl();
        address owner = ExecutorBot(impl).owner();
        console.log(owner);
        trade.setFee(1e4, 1000, sender);

        // trade.swapExactTokensForTokensFromTreasuryV3(
        //     0x53eB7B6EF76d3a5b28F845EFf76280cF98DD7eeF,
        //     0,
        //     hex"3f219fc186338aec865d60e05c4aee071b6060d99dde838b6060c2404ab2164c3245240429acda5b61499e1d87d5c0bc9845f640c44e9b11c1686717bfb2485d1b",
        //     ISwapRouter.ExactInputSingleParams(
        //         0x44462D2f1E89a92bE16A5969B46e1bEAc6e949dc,
        //         0x4796660CB6D7D2cba7eA79C3A4586aB23ac84634,
        //         10000,
        //         0xc6D654e9557b2C8d852253CE2D4dB6C7a61B1CbC,
        //         1724610109,
        //         102164000000000000000,
        //         0,
        //         0
        //     )
        // );

        // uint16[] memory botIds = new uint16[](1);
        // botIds[0] = 3;
        // uint256[] memory amountIns = new uint256[](1);
        // amountIns[0] = 49549907168752572642;
        // trade.swapExactTokensForTokensFromBotsV3(
        //     0x53eB7B6EF76d3a5b28F845EFf76280cF98DD7eeF,
        //     botIds,
        //     amountIns,
        //     hex"8d2a8eae7d3bd67b85c032f5eff47c52b38b2f68f7dc5c96e4151df59daa55c46e2b8ea6fecc88914d111dcb276e8762008e5e31709c2f509e0769124b664b2a1b",
        //     ISwapRouter.ExactInputSingleParams(
        //         0x44462D2f1E89a92bE16A5969B46e1bEAc6e949dc,
        //         0x4796660CB6D7D2cba7eA79C3A4586aB23ac84634,
        //         10000,
        //         0x53eB7B6EF76d3a5b28F845EFf76280cF98DD7eeF,
        //         1724611747,
        //         49549907168752572642,
        //         0,
        //         0
        //     )
        // );

        // ERC20Mock usdt = new ERC20Mock("USDT", "USDT");
        // ERC20Mock usdt = ERC20Mock(0x44462D2f1E89a92bE16A5969B46e1bEAc6e949dc);
        // ERC20Mock token = new ERC20Mock("TEST", "TEST");

        // trade.setMaker(sender);
        // trade.depositFee{value: 1e16}(sender);
        // usdt.approve(address(trade), type(uint256).max);

        // token.approve(address(routerv2), type(uint256).max);
        // usdt.approve(address(routerv2), type(uint256).max);

        // IPancakeRouter01(routerv2).addLiquidity(
        //     address(token), address(usdt), 1e24, 1e24, 0, 0, sender, type(uint256).max
        // );
    }
}
