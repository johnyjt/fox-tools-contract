// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

library Address {
    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();
    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */

    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

contract ExecutorBot {
    address immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    /// @dev Only the owner is authorized to invoke this action.
    /// @param target Target address
    /// @param data data
    /// @param value eth amount
    function execute(address target, bytes calldata data, uint256 value) public returns (bytes memory) {
        require(msg.sender == owner, "not owner");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return Address.verifyCallResult(success, returndata);
    }
}
