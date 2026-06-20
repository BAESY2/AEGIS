// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title PessimisticPriceGuard — value collateral at its recent low, not its spike.
/// @notice The "2-day-low" borrow-power floor Inverse FiRM uses. Instead of letting a
///         borrow/mint be sized off an instantaneous (manipulable) price, it values the
///         action at the MINIMUM price observed over a trailing window. A manipulated
///         upward spike does not lower the floor (a min ignores highs), so it cannot be
///         borrowed against; borrow power tracks the conservative recent low and only
///         rises once a genuine higher price has *persisted* across the window.
///
///         Distinct from the TWAP guard (an average): this is a worst-case floor —
///         strictly conservative for the protocol, accepting that borrow power lags a
///         real price increase. ctx = abi.encode(price). Allows the action only if the
///         price used is within `tolBps` of the trailing-window minimum.
///
///         O(1) storage via two rolling windows (current + previous); the effective
///         floor is min(currentWindowMin, previousWindowMin).
contract PessimisticPriceGuard is IDefense {
    uint256 public immutable windowBlocks;
    uint256 public immutable tolBps;

    uint256 public curMin;
    uint256 public prevMin;
    uint256 public windowStart;

    constructor(uint256 _windowBlocks, uint256 _tolBps, uint256 initialPrice) {
        windowBlocks = _windowBlocks;
        tolBps = _tolBps;
        curMin = initialPrice;
        prevMin = initialPrice;
        windowStart = block.number;
    }

    function floor() public view returns (uint256) {
        return curMin < prevMin ? curMin : prevMin;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external returns (bool) {
        uint256 price = abi.decode(ctx, (uint256));

        // roll the window forward if it has elapsed
        if (block.number - windowStart >= windowBlocks) {
            prevMin = curMin;
            curMin = price;
            windowStart = block.number;
        } else if (price < curMin) {
            curMin = price; // a new low lowers the floor; a spike (high) does not
        }

        uint256 f = floor();
        uint256 ceil = f + (f * tolBps) / 10000;
        return price <= ceil;
    }
}
