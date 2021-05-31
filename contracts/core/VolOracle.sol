//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.3;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "../libraries/OracleLibrary.sol";
import {Welford} from "../libraries/Welford.sol";
import {IERC20Detailed} from "../interfaces/IERC20Detailed.sol";
import "hardhat/console.sol";

contract VolOracle {
    /**
     * Immutables
     */
    address public immutable pool;
    address public immutable baseCurrency;
    address public immutable quoteCurrency;
    uint32 public immutable period;
    uint8 private immutable baseCurrencyDecimals;
    uint32 private constant twapDuration = 7200;
    uint256 private constant commitPhaseDuration = 1800; // 30 minutes from 12am/12pm

    /**
     * Storage
     */
    struct Accumulator {
        // 2^16-1 = 65535. Max of 65k records.
        uint16 count;
        // Timestamp of the last record
        uint32 lastTimestamp;
        // Smaller size because prices denominated in USDC, max 7.9e27
        uint96 mean;
        // Stores the result of multiplicating prices
        uint112 m2;
    }

    Accumulator public accumulator;

    constructor(
        address _pool,
        address _baseCurrency,
        address _quoteCurrency,
        uint32 _period
    ) {
        pool = _pool;
        baseCurrency = _baseCurrency;
        quoteCurrency = _quoteCurrency;
        baseCurrencyDecimals = IERC20Detailed(_baseCurrency).decimals();
        period = _period;
    }

    function commit() external {
        (uint32 commitTimestamp, uint32 gapFromPeriod) = secondsFromPeriod();
        require(gapFromPeriod < commitPhaseDuration, "Not commit phase");

        uint256 price = twap();
        Accumulator storage accum = accumulator;

        require(block.timestamp >= accum.lastTimestamp + period, "Committed");

        (uint256 newCount, uint256 newMean, uint256 newM2) =
            Welford.update(accum.count, accum.mean, accum.m2, price);

        accum.count = uint16(newCount);
        accum.mean = uint96(newMean);
        accum.m2 = uint112(newM2);
        accum.lastTimestamp = commitTimestamp;
    }

    function stdev() external view returns (uint256) {
        return Welford.getStdev(accumulator.count, accumulator.m2);
    }

    function twap() public view returns (uint256) {
        (
            int56 oldestTickCumulative,
            int56 newestTickCumulative,
            uint32 duration
        ) = getTickCumulatives();

        int24 timeWeightedAverageTick =
            getTimeWeightedAverageTick(
                oldestTickCumulative,
                newestTickCumulative,
                duration
            );

        uint128 quoteAmount = uint128(1 * 10**baseCurrencyDecimals);

        return
            OracleLibrary.getQuoteAtTick(
                timeWeightedAverageTick,
                quoteAmount,
                baseCurrency,
                quoteCurrency
            );
    }

    function getTimeWeightedAverageTick(
        int56 olderTickCumulative,
        int56 newerTickCumulative,
        uint32 duration
    ) private pure returns (int24 timeWeightedAverageTick) {
        int56 tickCumulativesDelta = newerTickCumulative - olderTickCumulative;
        int24 _timeWeightedAverageTick = int24(tickCumulativesDelta / duration);

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % duration != 0))
            _timeWeightedAverageTick--;

        return _timeWeightedAverageTick;
    }

    function getTickCumulatives()
        private
        view
        returns (
            int56 oldestTickCumulative,
            int56 newestTickCumulative,
            uint32 duration
        )
    {
        IUniswapV3Pool uniPool = IUniswapV3Pool(pool);

        (, , uint16 newestIndex, uint16 observationCardinality, , , ) =
            uniPool.slot0();

        // Get the latest observation
        (uint32 newestTimestamp, int56 _newestTickCumulative, , ) =
            uniPool.observations(newestIndex);

        // Get the oldest observation
        uint256 oldestIndex = (newestIndex + 1) % observationCardinality;
        (uint32 oldestTimestamp, int56 _oldestTickCumulative, , ) =
            uniPool.observations(oldestIndex);

        uint32 _duration = newestTimestamp - oldestTimestamp;

        return (_oldestTickCumulative, _newestTickCumulative, _duration);
    }

    function secondsFromPeriod()
        private
        view
        returns (uint32 closestPeriod, uint32 gapFromPeriod)
    {
        uint32 timestamp = uint32(block.timestamp);
        uint32 rem = timestamp % period;
        if (rem < period / 2) {
            return (timestamp - rem, rem);
        }
        return (timestamp + period - rem, period - rem);
    }
}