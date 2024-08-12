// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IPancakeRouter02} from "./interfaces/IPancakeRouter02.sol";
import {IPancakePair} from "./interfaces/IPancakePair.sol";
import {IPancakeFactory} from "./interfaces/IPancakeFactory.sol";
import {PancakeLibrary} from "./libraries/PancakeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IExecutorBot {
    function execute(address target, bytes calldata data, uint256 value) external returns (bytes memory);
}

contract PancakeV2TradeV1 is Ownable, Multicall {
    using SafeERC20 for IERC20;

    address public immutable factory;

    address public executorBotImpl;

    mapping(address => address) public marker;
    mapping(address => uint256) public markerNonce;
    mapping(address => uint256) public treasuryFee;
    mapping(address => mapping(address => bool)) public pairWL;

    modifier onlyMaker(address _treasury, address _maker) {
        require(marker[_treasury] == _maker, "maker err");
        _;
    }

    //
    constructor(address _factory) Ownable(msg.sender) {
        factory = _factory;
    }

    function swapExactTokensForTokensFromBots(
        address _treasury,
        uint256 deadline,
        address[] memory path,
        uint16[] memory bots,
        uint256[] memory amountIns,
        uint256 amountOutMin,
        bytes memory signature
    ) public ensure(deadline, signature, _treasury) {
        address pair = PancakeLibrary.pairFor(factory, path[0], path[1]);
        require(pairWL[_treasury][pair], "pair wl err");
        uint256 _amountIn = 0;
        for (uint256 i = 0; i < amountIns.length; i++) {
            address _bot = createOrGetBot(_treasury, bots[i]);
            botApprove(_bot, path[0], address(this), amountIns[i]);
            IERC20(path[0]).safeTransferFrom(_bot, pair, amountIns[i]);
            _amountIn += amountIns[i];
        }
        uint256[] memory amounts = PancakeLibrary.getAmountsOut(factory, _amountIn, path);
        _swap(amounts, path, _treasury, pair);
        require(amounts[1] >= amountOutMin, "PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactTokensForTokensFromTreasury(
        address _treasury,
        uint256 deadline,
        address[] memory path,
        address[] memory tos,
        uint256[] memory amountIns,
        uint256 amountOutMin,
        bytes memory signature
    ) public ensure(deadline, signature, _treasury) {
        address pair = PancakeLibrary.pairFor(factory, path[0], path[1]);
        require(pairWL[_treasury][pair], "pair wl err");
        uint256 out;
        for (uint256 i = 0; i < amountIns.length; i++) {
            uint256[] memory amounts = PancakeLibrary.getAmountsOut(factory, amountIns[i], path);
            IERC20(path[0]).safeTransferFrom(_treasury, pair, amounts[0]);
            _swap(amounts, path, tos[i], pair);
            out += amounts[1];
        }
        require(out >= amountOutMin, "PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address to, address pair) private {
        (address input, address output) = (path[0], path[1]);
        (address token0,) = PancakeLibrary.sortTokens(input, output);
        uint256 amountOut = amounts[1];
        (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IPancakePair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokensFromBots(
        address _treasury,
        uint256 deadline,
        address[] memory path,
        uint16[] memory bots,
        uint256[] memory amountIns,
        uint256 amountOutMin,
        bytes memory signature
    ) public ensure(deadline, signature, _treasury) {
        address pair = PancakeLibrary.pairFor(factory, path[0], path[1]);
        require(pairWL[_treasury][pair], "pair wl err");
        for (uint256 i = 0; i < amountIns.length; i++) {
            address _bot = createOrGetBot(_treasury, bots[i]);
            botApprove(_bot, path[0], address(this), amountIns[i]);
            IERC20(path[0]).safeTransferFrom(_bot, pair, amountIns[i]);
        }
        uint256 balanceBefore = IERC20(path[1]).balanceOf(_treasury);
        _swapSupportingFeeOnTransferTokens(path, _treasury, pair);
        require(
            IERC20(path[1]).balanceOf(_treasury) - balanceBefore >= amountOutMin,
            "PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokensFromTreasury(
        address _treasury,
        uint256 deadline,
        address[] memory path,
        address[] memory tos,
        uint256[] memory amountIns,
        uint256 amountOutMin,
        bytes memory signature
    ) public ensure(deadline, signature, _treasury) {
        address pair = PancakeLibrary.pairFor(factory, path[0], path[1]);
        require(pairWL[_treasury][pair], "pair wl err");
        uint256 out;
        for (uint256 i = 0; i < amountIns.length; i++) {
            IERC20(path[0]).safeTransferFrom(_treasury, pair, amountIns[i]);
            uint256 balanceBefore = IERC20(path[1]).balanceOf(tos[i]);
            _swapSupportingFeeOnTransferTokens(path, tos[i], pair);
            uint256 _bal = IERC20(path[1]).balanceOf(tos[i]) - balanceBefore;
            out += _bal;
        }
        require(out >= amountOutMin, "PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address to, address _pair) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = PancakeLibrary.sortTokens(input, output);
            IPancakePair pair = IPancakePair(_pair);
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = PancakeLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    modifier ensure(uint256 deadline, bytes memory signature, address _treasury) {
        uint256 gas1 = gasleft();
        address _marker = marker[_treasury];

        require(deadline >= block.timestamp, "PancakeRouter: EXPIRED");
        require(deadline > markerNonce[_marker], "nonce used");
        bytes32 hash = keccak256(abi.encodePacked(deadline));
        require(verify(hash, signature, _marker), "sig err");
        markerNonce[_marker] = deadline;
        _;
        uint256 gas2 = gasleft();
        uint256 fee = (gas1 - gas2 + 40000) * tx.gasprice;
        treasuryFee[_treasury] -= fee;
        payable(msg.sender).transfer(fee);
    }

    function getBotInfo(
        address _treasury,
        uint16 startIndex,
        uint16 endIndex,
        address token,
        uint256 amountOut,
        address[] memory path
    ) external view returns (uint256[] memory bals, uint256[] memory amounts) {
        uint256 size = endIndex - startIndex;
        bals = new uint256[](size);
        for (uint16 i = startIndex; i < endIndex; i++) {
            address bot = getBotAddr(_treasury, i);
            if (token != address(0)) {
                bals[i - startIndex] = IERC20(token).balanceOf(bot);
            }
        }
        if (amountOut > 0 && path.length > 1) {
            amounts = PancakeLibrary.getAmountsIn(factory, amountOut, path);
        }
    }

    function botApprove(address _bot, address _token, address _spender, uint256 amount) private {
        uint256 _allowance = IERC20(_token).allowance(_bot, _spender);
        if (_allowance < amount) {
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, _spender, type(uint256).max);
            IExecutorBot(_bot).execute(_token, data, 0);
        }
    }

    function botTransfer(address _bot, address _token, address to, uint256 amount) private {
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        IExecutorBot(_bot).execute(_token, transferData, 0);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        amounts = PancakeLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        amounts = PancakeLibrary.getAmountsIn(factory, amountOut, path);
    }

    receive() external payable {
        treasuryFee[msg.sender] += msg.value;
    }

    // batch transfer eth
    function collect(address _treasury, uint16[] memory botIds, address _token)
        external
        onlyMaker(_treasury, msg.sender)
    {
        for (uint256 i = 0; i < botIds.length; i++) {
            address _bot = createOrGetBot(_treasury, botIds[i]);
            botTransfer(_bot, _token, _treasury, IERC20(_token).balanceOf(_bot));
        }
    }

    function createOrGetBot(address _treasury, uint16 botId) public returns (address _bot) {
        require(botId < 2 ** 12, "bot id err");
        _bot = getBotAddr(_treasury, botId);
        if (!isContract(_bot)) {
            Clones.cloneDeterministic(executorBotImpl, bytes32(uint256(uint160(_treasury)) << 12 | botId));
        }
    }

    function getBotAddr(address _treasury, uint16 botId) public view returns (address) {
        require(botId < 2 ** 12, "bot id err");
        return Clones.predictDeterministicAddress(
            executorBotImpl, bytes32(uint256(uint160(_treasury)) << 12 | botId), address(this)
        );
    }

    function getBotAddrs(address _treasury, uint16 start, uint16 end) public view returns (address[] memory bots) {
        require(start < 2 ** 12, "start err");
        require(end < 2 ** 12, "end err");
        bots = new address[](end - start + 1);
        for (uint16 botId = start; botId <= end; botId++) {
            bots[botId - start] = Clones.predictDeterministicAddress(
                executorBotImpl, bytes32(uint256(uint160(_treasury)) << 12 | botId), address(this)
            );
        }
    }

    function getPair(address token0, address token1) public view returns (address pair) {
        pair = PancakeLibrary.pairFor(factory, token0, token1);
    }

    function setBotImpl(address _botImpl) external onlyOwner {
        require(executorBotImpl == address(0), "ex err");
        executorBotImpl = _botImpl;
    }

    function isContract(address account) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    //set maker
    function setMaker(address maker) external {
        marker[msg.sender] = maker;
    }

    //set pair
    function setPair(address pair, bool wl) external {
        pairWL[msg.sender][pair] = wl;
    }

    //withdraw fee
    function withdrawFee(address _treasury) external {
        require(msg.sender == _treasury || msg.sender == marker[_treasury], "a err");
        uint256 val = treasuryFee[_treasury];
        require(val > 0, "valf err");
        treasuryFee[_treasury] = 0;
        payable(msg.sender).transfer(val);
    }

    // batch transfer eth
    function batchTransferEth(address[] memory addrs, uint256 amount) external payable {
        require(msg.value >= amount * addrs.length,"bte");
        for (uint256 i = 0; i < addrs.length; i++) {
            payable(addrs[i]).transfer(amount);
        }
    }

    // batch transfer token
    function batchTransferToken(address[] memory addrs, uint256 amount, address token) external {
        for (uint256 i = 0; i < addrs.length; i++) {
            IERC20(token).safeTransferFrom(msg.sender, addrs[i], amount);
        }
    }

    function verify(bytes32 hash, bytes memory signature, address expectedSigner) public pure returns (bool) {
        bytes32 _hash = MessageHashUtils.toEthSignedMessageHash(hash);
        address recoveredSigner = ECDSA.recover(_hash, signature);
        return recoveredSigner == expectedSigner;
    }

    function depositFee(address _treasury) public payable {
        require(msg.value > 0, "val err");
        treasuryFee[_treasury] += msg.value;
    }
}
