// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/abdk-libraries-solidity/ABDKMath64x64.sol";
import "../lib/Bytes4Set.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Racer {
    using ABDKMath64x64 for int128;
    using Counters for Counters.Counter;
    using Bytes4Set for Bytes4Set.Set;

    struct Vote {
        // vote id (restricted to current cycle)
        uint256 voteId;
        // four byte symbol of the vote
        bytes4 symbol;
        // the address that placed the vote
        address placer;
        // represents if the reward was claimed or not
        bool claimed;
        // the cycle the vote belongs to
        uint256 cycleId;
        // block number in which this vote placed
        uint256 placedInBlock;
    }

    struct Cycle {
        // cycle id
        uint256 id;
        // the current cycle's starting block
        uint256 startingBlock;
        // amount of blocks the cycle will run for
        uint256 endingBlock;
        // the cost of one vote in wei
        uint256 votePrice;
        // the address of the cycle creator
        address creator;
        // vote id counter for this cycle
        Counters.Counter voteIdCounter;
        // flag for checking existence of cycle
        bool exists;
        // current reward pool balance
        uint256 balance;
        // the final base reward
        int128 baseReward;
        // the final normalization factor for the cycle
        int128 normalizationFactor;
    }

    struct Symbol {
        bytes4 symbol;
        uint256 voteCount;
        uint pointer;
    }

    event CycleCreated(
        address indexed creator,
        uint256 indexed id,
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    );

    event VotePlaced(
        address indexed placer,
        uint256 voteId,
        uint256 indexed cycleId,
        bytes4 indexed symbol,
        uint256 amount
    );

    event VoteClaimed(
        address indexed claimer,
        uint256 indexed cycleId,
        bytes4 indexed symbol,
        int128 amount
    );

    // cycle id -> symbol -> vote id array
    mapping(uint256 => mapping(bytes4 => uint256[])) votesMeta;

    // store here top three most voted symbols (for caching purposes)
    // we use pointers to the symbol set items
    mapping(uint256 => uint[]) topThreeSymbols;

    // cycle id -> symbols people voted for
    mapping(uint256 => Bytes4Set.Set) symbols;

    // cycle id -> cycle
    mapping(uint256 => Cycle) cycles;

    Counters.Counter cycleIdCounter;

    // cycle id -> vote id -> vote
    mapping(uint256 => mapping(uint256 => Vote)) votes;

    constructor() {}

    // Places votes based on how much wei was sent
    function placeVote(
        uint256 cycleId,
        bytes4 symbol
    ) public payable returns (uint256) {
        require(cycles[cycleId].exists, "cycle doesn't exist");
        require(
            cycles[cycleId].startingBlock <= block.number,
            "cycle hasn't started yet"
        );
        uint256 amount = msg.value;
        require(
            amount == cycles[cycleId].votePrice,
            "incorrect wei amount for this cycle"
        );
        Cycle storage cycle = cycles[cycleId];
        cycle.voteIdCounter.increment();
        uint256 voteId = cycle.voteIdCounter.current();
        votes[cycleId][voteId] = Vote(
            voteId,
            symbol,
            msg.sender,
            false,
            cycleId,
            block.number
        );
        votesMeta[cycleId][symbol].push(voteId);
        if (!symbols[cycleId].exists(symbol)) {
            symbols[cycleId].insert(symbol);
        }
        cycle.balance += cycle.votePrice;

        updateTopThreeSymbols(cycleId);

        emit VotePlaced(msg.sender, voteId, cycleId, symbol, amount);
        return voteId;
    }

    // update top three most voted symbols
    function updateTopThreeSymbols(uint256 cycleId) internal {
        bool init = topThreeSymbols[cycleId].length != 0;
        Symbol memory first = Symbol("", 0, 0);
        Symbol memory second = Symbol("", 0, 0);
        Symbol memory third = Symbol("", 0, 0);
        for (uint i = 0; i < symbols[cycleId].count(); i++) {
            bytes4 symbol = symbols[cycleId].get(i);
            uint256 voteCount = votesMeta[cycleId][symbol].length;
            if (voteCount > first.voteCount) {
                second = first;
                first = Symbol(symbol, voteCount, i);
            } else if (voteCount > second.voteCount) {
                third = second;
                second = Symbol(symbol, voteCount, i);
            } else if (voteCount > third.voteCount) {
                third = Symbol(symbol, voteCount, i);
            }
        }

        if (init) {
            topThreeSymbols[cycleId].push(first.pointer);
            topThreeSymbols[cycleId].push(second.pointer);
            topThreeSymbols[cycleId].push(third.pointer);
        } else {
            topThreeSymbols[cycleId][0] = first.pointer;
            topThreeSymbols[cycleId][1] = second.pointer;
            topThreeSymbols[cycleId][2] = third.pointer;
        }
    }

    function createCycle(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    ) public returns (uint256) {
        uint256 cycleId = cycleIdCounter.current();
        cycles[cycleId] = Cycle(
            cycleId,
            startingBlock,
            startingBlock + blockLength,
            votePrice,
            msg.sender,
            Counters.Counter(0),
            true,
            0,
            0,
            0
        );

        emit CycleCreated(
            msg.sender,
            cycleId,
            startingBlock,
            blockLength,
            votePrice
        ); 
        cycleIdCounter.increment();
        return cycleId;
    }

    // WARN! This function should be called only once cuz it's very expensive on gas
    function calculateNormalizedFactor(
        uint256 cycleId
    ) public view returns (int128) {
        require(cycles[cycleId].exists, "invalid cycle id");
        require(
            cycles[cycleId].endingBlock < block.number,
            "cannot calculate normalization factor while cycle is not ended"
        );
        Cycle storage cycle = cycles[cycleId];

        int128 normalizationFactor = 0;

        // summing points from the first symbol
        for (
            uint i = 0;
            i <
            votesMeta[cycleId][
                symbols[cycleId].get(topThreeSymbols[cycleId][0])
            ].length;
            i++
        ) {
            Vote storage vote = votes[cycleId][i];
            int128 rewardPoint = calculatePoint(cycle, vote, 1);
            normalizationFactor = ABDKMath64x64.add(
                normalizationFactor,
                rewardPoint
            );
        }

        // summing points from the second symbol
        for (
            uint i = 0;
            i <
            votesMeta[cycleId][
                symbols[cycleId].get(topThreeSymbols[cycleId][1])
            ].length;
            i++
        ) {
            Vote storage vote = votes[cycleId][i];
            int128 rewardPoint = calculatePoint(cycle, vote, 2);
            normalizationFactor = ABDKMath64x64.add(
                normalizationFactor,
                rewardPoint
            );
        }

        // summing points from the third symbol
        for (
            uint i = 0;
            i <
            votesMeta[cycleId][
                symbols[cycleId].get(topThreeSymbols[cycleId][2])
            ].length;
            i++
        ) {
            Vote storage vote = votes[cycleId][i];
            int128 rewardPoint = calculatePoint(cycle, vote, 3);
            normalizationFactor = ABDKMath64x64.add(
                normalizationFactor,
                rewardPoint
            );
        }

        normalizationFactor = ABDKMath64x64.div(
            normalizationFactor,
            ABDKMath64x64.fromUInt(cycle.voteIdCounter.current())
        );

        return normalizationFactor;
    }

    function getVoteTimeliness(
        Cycle storage cycle,
        Vote storage vote
    ) internal view returns (int128) {
        return
            ABDKMath64x64.divu(
                vote.placedInBlock - cycle.startingBlock,
                cycle.endingBlock - cycle.startingBlock
            );
    }

    function calculatePoint(
        Cycle storage cycle,
        Vote storage vote,
        uint place
    ) internal view returns (int128) {
        require(place >= 1 && place <= 3, "incorrect place value");
        int128 timeliness = getVoteTimeliness(cycle, vote);
        int128 rewardPoint = ABDKMath64x64.fromUInt(0);
        if (place == 0) {
            rewardPoint = ABDKMath64x64.pow(
                ABDKMath64x64.sub(timeliness, 1),
                2
            );
        } else if (place == 1) {
            rewardPoint = ABDKMath64x64.pow(
                ABDKMath64x64.sub(
                    ABDKMath64x64.div(timeliness, 2),
                    ABDKMath64x64.div(1, 2)
                ),
                2
            );
        } else if (place == 2) {
            rewardPoint = ABDKMath64x64.pow(
                ABDKMath64x64.sub(
                    ABDKMath64x64.div(timeliness, 3),
                    ABDKMath64x64.div(1, 3)
                ),
                2
            );
        }
        return rewardPoint;
    }

    function getBaseReward(Cycle storage cycle) internal view returns (int128) {
        return ABDKMath64x64.divu(cycle.balance, cycle.voteIdCounter.current());
    }

    function getVotePlace(
        Cycle storage cycle,
        Vote storage vote
    ) internal view returns (uint) {
        bool topThreeSymbolsVote = false;
        uint place;
        for (uint i = 0; i < 3; i++) {
            bytes4 symbol = symbols[cycle.id].get(topThreeSymbols[cycle.id][i]);
            if (symbol == vote.symbol) {
                topThreeSymbolsVote = true;
                place = i;
                break;
            }
        }
        require(topThreeSymbolsVote, "your vote is not for top three symbols");
        return place;
    }

    function calculateReward(
        uint256 cycleId,
        uint256 voteId
    ) public view returns (int128) {
        require(cycles[cycleId].exists, "invalid cycle");
        require(votes[cycleId][voteId].placedInBlock != 0, "invalid vote");
        Cycle storage cycle = cycles[cycleId];
        Vote storage vote = votes[cycleId][voteId];
        require(
            cycle.normalizationFactor != 0,
            "normalization factor hasn't calculated yet"
        );
        require(cycle.baseReward != 0, "base reward hasn't calculated yet");

        uint place = getVotePlace(cycle, vote);

        int128 curvePoint = calculatePoint(cycle, vote, place);
        int128 normalizedReward = ABDKMath64x64.mul(
            ABDKMath64x64.mul(cycle.baseReward, curvePoint),
            cycle.normalizationFactor
        );
        return normalizedReward;
    }

    function claimReward(uint256 cycleId, uint256 voteId) public {
        require(cycles[cycleId].exists, "invalid cycle");
        Cycle storage cycle = cycles[cycleId];
        require(block.number > cycle.endingBlock, "cycle has not ended yet");
        Vote storage vote = votes[cycleId][voteId];
        require(vote.placedInBlock != 0, "invalid vote");

        uint place = getVotePlace(cycle, vote);
        // reward claiming restriction based on timeliness of vote
        int128 timeliness = getVoteTimeliness(cycle, vote);
        if (
            (place == 1 && timeliness >= ABDKMath64x64.div(2, 3)) ||
            (place == 2 && timeliness >= ABDKMath64x64.div(1, 3))
        ) {
            require(
                msg.sender == cycle.creator,
                "vote is placed late so claiming reward for this vote is restricted to cycle creator"
            );
        } else {
            require(
                msg.sender == vote.placer,
                "you are not placer of that vote"
            );
        }

        if (cycle.normalizationFactor == 0) {
            cycle.normalizationFactor = calculateNormalizedFactor(cycleId); // this is expensive
        }
        if (cycle.baseReward == 0) {
            cycle.baseReward = getBaseReward(cycle);
        }
        int128 normalizedReward = calculateReward(cycleId, voteId);
        payable(msg.sender).transfer(ABDKMath64x64.toUInt(normalizedReward));
        emit VoteClaimed(msg.sender, cycleId, vote.symbol, normalizedReward);
    }
}
