// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPancakeRouter01 {
    function factory() external pure returns (address);

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut);

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IPancakePair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function factory() external view returns (address);
}

interface IPancakeV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract ExecutorBot {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function execute(address target, bytes calldata data, uint256 value) public returns (bytes memory) {
        require(msg.sender == owner, "not owner");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return Address.verifyCallResult(success, returndata);
    }
}

contract PancakeV2TradeV1 is Ownable, Multicall {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable router;
    address public immutable factory3;
    address public immutable routerv3;
    address public immutable executorBotImpl;

    mapping(address => address) public marker;
    mapping(address => uint256) public markerNonce;
    mapping(address => uint256) public treasuryFee;
    mapping(address => mapping(address => bool)) public pairWL;

    //manager
    uint256 public monthFee;
    uint256 public feeRate; // 10000
    address public feeReceiver;
    mapping(address => mapping(uint256 => uint256)) public curMonthFee;

    modifier onlyMaker(address _treasury, address _maker) {
        require(marker[_treasury] == _maker, "maker err");
        _;
    }

    constructor(address _router, address _routerv3) Ownable(msg.sender) {
        router = _router;
        routerv3 = _routerv3;
        factory = IPancakeRouter01(_router).factory();
        factory3 = ISwapRouter(_routerv3).factory();
        executorBotImpl = address(new ExecutorBot(address(this)));
    }

    function swapExactTokensForTokensFromTreasury(
        address _treasury,
        uint256 deadline,
        address[] memory path,
        uint16 botId,
        uint256 amountIn,
        uint256 amountOutMin,
        bool isFee,
        bytes memory signature
    )
        public
        ensure(
            deadline,
            signature,
            _treasury,
            msg.sender,
            keccak256(abi.encodePacked(uint8(0), deadline, path, botId, amountIn, amountOutMin, isFee, msg.sender))
        )
    {
        address pair = IPancakeFactory(factory).getPair(path[0], path[1]);
        require(pairWL[_treasury][pair], "pair wl err");
        IERC20(path[0]).safeTransferFrom(_treasury, pair, amountIn);
        address _bot = getBotAddr(_treasury, botId);
        _internalSwap(isFee, amountIn, path, _bot, pair, amountOutMin);
    }

    //v2
    function swapExactTokensForTokensFromBots(
        address _treasury,
        uint256 deadline,
        address[] memory path,
        uint16[] memory botIds,
        uint256[] memory amountIns,
        uint256 amountOutMin,
        bool isFee,
        bytes memory signature
    )
        public
        ensure(
            deadline,
            signature,
            _treasury,
            msg.sender,
            keccak256(abi.encodePacked(uint8(1), deadline, path, botIds, amountIns, amountOutMin, isFee, msg.sender))
        )
    {
        address pair = IPancakeFactory(factory).getPair(path[0], path[1]);
        require(pairWL[_treasury][pair], "pair wl err");
        uint256 _amountIn = 0;
        for (uint256 i = 0; i < amountIns.length; i++) {
            address _bot = createOrGetBot(_treasury, botIds[i]);
            botApprove(_bot, path[0], address(this), amountIns[i]);
            IERC20(path[0]).safeTransferFrom(_bot, pair, amountIns[i]);
            _amountIn += amountIns[i];
        }
        _internalSwap(isFee, _amountIn, path, _treasury, pair, amountOutMin);
    }

    function _internalSwap(
        bool isFee,
        uint256 _amountIn,
        address[] memory path,
        address to,
        address pair,
        uint256 amountOutMin
    ) private {
        uint256 out;
        if (isFee) {
            out = _swapSupportingFeeOnTransferTokens(path, to, pair);
        } else {
            out = _swap(_amountIn, path, to, pair);
        }
        require(out >= amountOutMin, "PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256 _amountIn, address[] memory path, address to, address pair)
        private
        returns (uint256 amountOut)
    {
        uint256[] memory amounts = IPancakeRouter01(router).getAmountsOut(_amountIn, path);
        (address input, address output) = (path[0], path[1]);
        (address token0,) = sortTokens(input, output);
        amountOut = amounts[1];
        (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IPancakePair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address to, address _pair)
        private
        returns (uint256 amountOut)
    {
        uint256 balanceBefore = IERC20(path[1]).balanceOf(to);
        (address input, address output) = (path[0], path[1]);
        (address token0,) = sortTokens(input, output);
        IPancakePair pair = IPancakePair(_pair);
        uint256 amountInput;
        uint256 amountOutput;
        {
            // scope to avoid stack too deep errors
            (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
            (uint256 reserveInput, uint256 reserveOutput) =
                input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
            amountOutput = IPancakeRouter01(router).getAmountOut(amountInput, reserveInput, reserveOutput);
        }
        (uint256 amount0Out, uint256 amount1Out) =
            input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
        pair.swap(amount0Out, amount1Out, to, new bytes(0));
        amountOut = IERC20(path[1]).balanceOf(to) - balanceBefore;
    }

    //v3
    function swapExactTokensForTokensFromTreasuryV3(
        address _treasury,
        uint16 botId,
        bytes memory signature,
        ISwapRouter.ExactInputSingleParams calldata params
    )
        public
        ensure(
            params.deadline,
            signature,
            _treasury,
            msg.sender,
            keccak256(
                abi.encodePacked(
                    uint8(2),
                    botId,
                    params.tokenIn,
                    params.tokenOut,
                    params.fee,
                    params.recipient,
                    params.deadline,
                    params.amountIn,
                    params.amountOutMinimum,
                    params.sqrtPriceLimitX96,
                    msg.sender
                )
            )
        )
    {
        address pool = getPancakeV3Pool(params.tokenIn, params.tokenOut, params.fee);
        require(pairWL[_treasury][pool], "pool wl err");
        address _bot = createOrGetBot(_treasury, botId);
        IERC20(params.tokenIn).safeTransferFrom(_treasury, _bot, params.amountIn);
        _internalSwapV3(_bot, params);
    }

    function swapExactTokensForTokensFromBotsV3(
        address _treasury,
        uint16[] memory botIds,
        uint256[] memory amountIns,
        bytes memory signature,
        ISwapRouter.ExactInputSingleParams calldata params
    )
        public
        ensure(
            params.deadline,
            signature,
            _treasury,
            msg.sender,
            keccak256(
                abi.encodePacked(
                    uint8(3),
                    botIds,
                    amountIns,
                    params.tokenIn,
                    params.tokenOut,
                    params.fee,
                    params.recipient,
                    params.deadline,
                    params.amountIn,
                    params.amountOutMinimum,
                    params.sqrtPriceLimitX96,
                    msg.sender
                )
            )
        )
    {
        address pool = getPancakeV3Pool(params.tokenIn, params.tokenOut, params.fee);
        require(pairWL[_treasury][pool], "pool wl err");
        address senderBot = createOrGetBot(_treasury, botIds[0]);
        uint256 amountIn = amountIns[0];
        for (uint256 i = 1; i < botIds.length; i++) {
            address _bot = getBotAddr(_treasury, botIds[i]);
            botTransfer(_bot, params.tokenIn, senderBot, amountIns[i]);
            amountIn += amountIns[i];
        }
        require(amountIn == params.amountIn, "ai err");
        require(_treasury == params.recipient, "rec err");
        _internalSwapV3(senderBot, params);
    }

    function _internalSwapV3(address senderBot, ISwapRouter.ExactInputSingleParams calldata params) private {
        botApprove(senderBot, params.tokenIn, routerv3, params.amountIn);
        bytes memory data = abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params);
        ExecutorBot(senderBot).execute(routerv3, data, 0);
    }

    function getPancakeV3Pool(address tokenA, address tokenB, uint24 fee) public view returns (address pool) {
        return IPancakeV3Factory(factory3).getPool(tokenA, tokenB, fee);
    }

    modifier ensure(uint256 deadline, bytes memory signature, address _treasury, address sender, bytes32 hash) {
        uint256 gas1 = gasleft();
        require(!isContract(sender), "con err");
        address _marker = marker[_treasury];
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(deadline > markerNonce[_marker], "nonce used");
        require(verify(hash, signature, _marker), "sig err");
        markerNonce[_marker] = deadline;
        _;
        //handle sender fee and dao fee
        uint256 gas2 = gasleft();
        uint256 feeToSender = (gas1 - gas2 + 40000) * tx.gasprice;
        uint256 total = feeToSender;
        uint256 curMonth = block.timestamp / 30 days;
        if (curMonthFee[_treasury][curMonth] < monthFee && feeRate > 0) {
            feeToSender += 10000;
            uint256 feeToDao = feeRate * feeToSender / 10000;
            curMonthFee[_treasury][curMonth] += feeToDao;
            total = feeToSender + feeToDao;
            payable(feeReceiver).transfer(feeToDao);
        }
        treasuryFee[_treasury] -= total;
        payable(msg.sender).transfer(feeToSender);
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
            amounts = IPancakeRouter01(router).getAmountsIn(amountOut, path);
        }
    }

    function botApprove(address _bot, address _token, address _spender, uint256 amount) private {
        uint256 _allowance = IERC20(_token).allowance(_bot, _spender);
        if (_allowance < amount) {
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, _spender, type(uint256).max);
            ExecutorBot(_bot).execute(_token, data, 0);
        }
    }

    function botTransfer(address _bot, address _token, address to, uint256 amount) private {
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        ExecutorBot(_bot).execute(_token, transferData, 0);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        amounts = IPancakeRouter01(router).getAmountsOut(amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        amounts = IPancakeRouter01(router).getAmountsIn(amountOut, path);
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
        pair = IPancakeFactory(factory).getPair(token0, token1);
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
        require(msg.value >= amount * addrs.length, "bte");
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

    function depositDaoFee(address _treasury) public payable {
        require(msg.value > 0, "val err");
        uint256 curMonth = block.timestamp / 30 days;
        curMonthFee[_treasury][curMonth] += msg.value;
        payable(feeReceiver).transfer(msg.value);
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "PancakeLibrary: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "PancakeLibrary: ZERO_ADDRESS");
    }

    //manager
    function setFee(uint256 _monthFee, uint256 _feeRate, address _feeReceiver) external onlyOwner {
        require(feeRate < 10000, "fr err");
        monthFee = _monthFee;
        feeRate = _feeRate;
        feeReceiver = _feeReceiver;
    }
}
