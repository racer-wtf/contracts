// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "bytes4set/Bytes4Set.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Racer is ReentrancyGuard {
    using Math for uint256;
    using ABDKMath64x64 for int128;
    using Bytes4Set for Bytes4Set.Set;

    /**
     * @dev Struct representing a vote.
     * @param voteId The unique identifier for the vote.
     * @param symbol The four-byte symbol voted for.
     * @param placer The address that placed the vote.
     * @param claimed Represents if the reward was claimed or not.
     * @param cycleId The cycle the vote belongs to.
     * @param placedInBlock The block number in which this vote was placed.
     * @param exists Flag for checking the existence of the vote.
     */
    struct Vote {
        uint256 voteId;
        bytes4 symbol;
        address placer;
        bool claimed;
        uint256 cycleId;
        uint256 placedInBlock;
        bool exists;
    }

    /**
     * @dev Struct representing a cycle.
     * @param id The unique identifier for the cycle.
     * @param startingBlock The current cycle's starting block.
     * @param endingBlock The block number when the cycle ends.
     * @param votePrice The cost of one vote in wei.
     * @param creator The address of the cycle creator.
     * @param voteIdCounter Vote id counter for this cycle.
     * @param exists Flag for checking the existence of the cycle.
     * @param balance Current reward pool balance.
     * @param baseReward The final base reward.
     * @param normalizationFactor The final normalization factor for the cycle.
     */
    struct Cycle {
        uint256 id;
        uint256 startingBlock;
        uint256 endingBlock;
        uint256 votePrice;
        address creator;
        uint256 voteIdCounter;
        bool exists;
        uint256 balance;
        int128 baseReward;
        int128 normalizationFactor;
    }

    /**
     * @dev Struct representing a symbol.
     * @param symbol The four-byte symbol.
     * @param voteCount The number of votes for this symbol.
     * @param pointer Pointer to the symbol set item.
     */
    struct Symbol {
        bytes4 symbol;
        uint256 voteCount;
        uint256 pointer;
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
        bytes4 indexed symbol
    );

    event VoteClaimed(
        address indexed claimer,
        uint256 indexed cycleId,
        bytes4 indexed symbol,
        uint256 amount
    );

    // cycle id -> symbol -> vote id array
    mapping(uint256 => mapping(bytes4 => uint256[])) votesMeta;

    // store here top three most voted symbols (for caching purposes)
    // we use pointers to the symbol set items
    mapping(uint256 => uint256[3]) topThreeSymbols;

    // cycle id -> symbols people voted for
    mapping(uint256 => Bytes4Set.Set) symbols;

    // cycle id -> cycle
    mapping(uint256 => Cycle) cycles;

    uint256 cycleIdCounter;

    // cycle id -> vote id -> vote
    mapping(uint256 => mapping(uint256 => Vote)) votes;

    /**
     * @dev Places votes based on how much wei was sent.
     * @param cycleId The cycle ID for which the vote is placed.
     * @param symbol The four-byte symbol to vote for.
     * @return voteId The unique identifier for the vote.
     */
    function placeVote(
        uint256 cycleId,
        bytes4 symbol
    ) public payable returns (uint256) {
        require(cycles[cycleId].exists, "cycle doesn't exist");
        require(
            cycles[cycleId].startingBlock <= block.number &&
                cycles[cycleId].endingBlock >= block.number,
            "voting is unavailable"
        );
        uint256 amount = msg.value;
        require(
            amount == cycles[cycleId].votePrice,
            "incorrect wei amount for this cycle"
        );
        Cycle storage cycle = cycles[cycleId];
        uint256 voteId = cycle.voteIdCounter++;
        votes[cycleId][voteId] = Vote(
            voteId,
            symbol,
            msg.sender,
            false,
            cycleId,
            block.number,
            true
        );
        votesMeta[cycleId][symbol].push(voteId);
        if (!symbols[cycleId].exists(symbol)) {
            symbols[cycleId].insert(symbol);
        }
        cycle.balance += cycle.votePrice;

        updateTopThreeSymbols(cycleId);

        emit VotePlaced(msg.sender, voteId, cycleId, symbol);
        return voteId;
    }

    /**
     * @dev Updates the top three most voted symbols for a cycle.
     * @param cycleId The cycle ID to update the top symbols for.
     */
    function updateTopThreeSymbols(uint256 cycleId) internal {
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

        topThreeSymbols[cycleId][0] = first.pointer;
        topThreeSymbols[cycleId][1] = second.pointer;
        topThreeSymbols[cycleId][2] = third.pointer;
    }

    /**
     * @dev Creates a new voting cycle.
     * @param startingBlock The block number when the cycle starts.
     * @param blockLength The number of blocks the cycle will run for.
     * @param votePrice The cost of one vote in wei.
     * @return cycleId The unique identifier for the created cycle.
     */
    function createCycle(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    ) public returns (uint256) {
        require(votePrice > 0, "vote price must be greater than 0");

        uint256 cycleId = cycleIdCounter;
        cycles[cycleId] = Cycle(
            cycleId,
            startingBlock,
            startingBlock + blockLength,
            votePrice,
            msg.sender,
            0,
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
        cycleIdCounter++;
        return cycleId;
    }

    /**
     * @dev Gets information about a cycle.
     * @param cycleId The cycle ID to retrieve information for.
     * @return startingBlock The starting block of the cycle.
     * @return endingBlock The ending block of the cycle.
     * @return votePrice The cost of one vote in wei.
     * @return creator The address of the cycle creator.
     * @return balance The current reward pool balance.
     * @return totalVotes The total number of votes in the cycle.
     */
    function getCycle(
        uint256 cycleId
    )
        public
        view
        returns (
            uint256 startingBlock,
            uint256 endingBlock,
            uint256 votePrice,
            address creator,
            uint256 balance,
            uint256 totalVotes
        )
    {
        Cycle storage cycle = cycles[cycleId];
        require(cycle.exists, "cycle doesn't exist");
        startingBlock = cycle.startingBlock;
        endingBlock = cycle.endingBlock;
        votePrice = cycle.votePrice;
        creator = cycle.creator;
        balance = cycle.balance;
        for (uint i = 0; i < symbols[cycleId].count(); i++) {
            totalVotes += votesMeta[cycleId][symbols[cycleId].get(i)].length;
        }
    }

    /**
     * @dev Calculates the normalized factor for a cycle, which is used to calculate rewards.
     * @notice This function is very gas-costly and should be called only once per cycle.
     * @param cycleId The cycle ID to calculate the normalized factor for.
     * @return normalizationFactor The calculated normalization factor.
     */
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
        bytes4 firstSymbol = symbols[cycleId].get(topThreeSymbols[cycleId][0]);
        for (uint i = 0; i < votesMeta[cycleId][firstSymbol].length; i++) {
            Vote storage vote = votes[cycleId][
                votesMeta[cycleId][firstSymbol][i]
            ];
            int128 rewardPoint = calculatePoint(cycle, vote, 0);
            normalizationFactor = ABDKMath64x64.add(
                normalizationFactor,
                rewardPoint
            );
        }

        if (topThreeSymbols[cycleId][0] != topThreeSymbols[cycleId][1]) {
            // summing points from the second symbol
            bytes4 secondSymbol = symbols[cycleId].get(
                topThreeSymbols[cycleId][1]
            );
            for (uint i = 0; i < votesMeta[cycleId][secondSymbol].length; i++) {
                Vote storage vote = votes[cycleId][
                    votesMeta[cycleId][secondSymbol][i]
                ];
                int128 rewardPoint = calculatePoint(cycle, vote, 1);
                normalizationFactor = ABDKMath64x64.add(
                    normalizationFactor,
                    rewardPoint
                );
            }
        }

        if (topThreeSymbols[cycleId][0] != topThreeSymbols[cycleId][2]) {
            // summing points from the third symbol
            bytes4 thirdSymbol = symbols[cycleId].get(
                topThreeSymbols[cycleId][2]
            );
            for (
                uint256 i = 0;
                i < votesMeta[cycleId][thirdSymbol].length;
                i++
            ) {
                Vote storage vote = votes[cycleId][
                    votesMeta[cycleId][thirdSymbol][i]
                ];
                int128 rewardPoint = calculatePoint(cycle, vote, 2);
                normalizationFactor = ABDKMath64x64.add(
                    normalizationFactor,
                    rewardPoint
                );
            }
        }

        normalizationFactor = ABDKMath64x64.div(
            normalizationFactor,
            ABDKMath64x64.fromUInt(cycle.voteIdCounter)
        );
        normalizationFactor = ABDKMath64x64.div(
            ABDKMath64x64.fromUInt(1),
            normalizationFactor
        );
        return normalizationFactor;
    }

    /**
     * @dev Calculates the timeliness of a vote within a cycle.
     * @param cycle The Cycle storage struct.
     * @param vote The Vote storage struct.
     * @return timeliness The calculated timeliness of the vote.
     */
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

    /**
     * @dev Calculates the reward point for a vote within a cycle.
     * @param cycle The Cycle storage struct.
     * @param vote The Vote storage struct.
     * @param place The place of the vote among the top three symbols.
     * @return rewardPoint The calculated reward point for the vote.
     */
    function calculatePoint(
        Cycle storage cycle,
        Vote storage vote,
        uint place
    ) internal view returns (int128) {
        require(place >= 0 && place <= 2, "incorrect place value");
        int128 timeliness = getVoteTimeliness(cycle, vote);
        int128 rewardPoint;
        if (place == 0) {
            rewardPoint = ABDKMath64x64.pow(
                ABDKMath64x64.sub(timeliness, ABDKMath64x64.fromUInt(1)),
                2
            );
        } else if (place == 1) {
            rewardPoint = ABDKMath64x64.pow(
                ABDKMath64x64.sub(
                    ABDKMath64x64.div(timeliness, ABDKMath64x64.fromUInt(2)),
                    ABDKMath64x64.divu(1, 2)
                ),
                2
            );
        } else if (place == 2) {
            rewardPoint = ABDKMath64x64.pow(
                ABDKMath64x64.sub(
                    ABDKMath64x64.div(timeliness, ABDKMath64x64.fromUInt(3)),
                    ABDKMath64x64.divu(1, 3)
                ),
                2
            );
        }

        return rewardPoint;
    }

    /**
     * @dev Calculates the base reward for a cycle.
     * @param cycle The Cycle storage struct.
     * @return baseReward The calculated base reward for the cycle.
     */
    function getBaseReward(Cycle storage cycle) internal view returns (int128) {
        return ABDKMath64x64.divu(cycle.balance, cycle.voteIdCounter);
    }

    /**
     * @dev Gets the place of a vote within the top three symbols of a cycle.
     * @param cycle The Cycle storage struct.
     * @param vote The Vote storage struct.
     * @return place The place of the vote (0, 1, or 2) or -1 if not in the top three.
     */
    function getVotePlace(
        Cycle storage cycle,
        Vote storage vote
    ) internal view returns (int) {
        bool topThreeSymbolsVote = false;
        int place = -1;
        for (uint i = 0; i < 3; i++) {
            bytes4 symbol = symbols[cycle.id].get(topThreeSymbols[cycle.id][i]);
            if (symbol == vote.symbol) {
                topThreeSymbolsVote = true;
                place = int(i);
                break;
            }
        }
        return place;
    }

    /**
     * @dev Calculates the normalized reward for a vote within a cycle.
     * @param cycleId The cycle ID the vote belongs to.
     * @param voteId The unique identifier for the vote.
     * @return normalizedReward The calculated normalized reward for the vote.
     */
    function calculateReward(
        uint256 cycleId,
        uint256 voteId
    ) public view returns (int128) {
        require(cycles[cycleId].exists, "invalid cycle");
        require(votes[cycleId][voteId].exists, "invalid vote");
        Cycle storage cycle = cycles[cycleId];
        Vote storage vote = votes[cycleId][voteId];
        require(
            cycle.normalizationFactor != 0,
            "normalization factor hasn't calculated yet"
        );
        require(cycle.baseReward != 0, "base reward hasn't calculated yet");

        int place = getVotePlace(cycle, vote);
        require(place >= 0, "vote not for top three symbols");

        int128 curvePoint = calculatePoint(cycle, vote, uint(place));
        int128 normalizedReward = ABDKMath64x64.mul(
            ABDKMath64x64.mul(cycle.baseReward, curvePoint),
            cycle.normalizationFactor
        );
        return normalizedReward;
    }

    /**
     * @dev Checks if claiming a reward for a vote is available.
     * @param cycleId The cycle ID the vote belongs to.
     * @param voteId The unique identifier for the vote.
     * @return available True if claiming the reward is available, false otherwise.
     */
    function isClaimingRewardAvailable(
        uint256 cycleId,
        uint256 voteId
    ) public view returns (bool) {
        Cycle storage cycle = cycles[cycleId];
        require(cycle.exists, "invalid cycle");
        if (block.number <= cycle.endingBlock) return false;
        Vote storage vote = votes[cycleId][voteId];
        require(vote.exists, "invalid vote");

        int place = getVotePlace(cycle, vote);
        if (place < 0) return false;
        int128 timeliness = getVoteTimeliness(cycle, vote);
        if (
            (place == 1 && timeliness >= ABDKMath64x64.divu(2, 3)) ||
            (place == 2 && timeliness >= ABDKMath64x64.divu(1, 3))
        ) {
            if (msg.sender != cycle.creator) return false;
        } else {
            if (msg.sender != vote.placer) return false;
        }
        return true;
    }

    /**
     * @dev Claims the reward for a vote in a cycle.
     * @param cycleId The cycle ID the vote belongs to.
     * @param voteId The unique identifier for the vote.
     */
    function claimReward(uint256 cycleId, uint256 voteId) public nonReentrant {
        require(cycles[cycleId].exists, "invalid cycle");
        Cycle storage cycle = cycles[cycleId];
        require(block.number > cycle.endingBlock, "cycle has not ended yet");
        Vote storage vote = votes[cycleId][voteId];
        require(vote.exists, "invalid vote");
        require(!vote.claimed, "vote already has been claimed");

        int place = getVotePlace(cycle, vote);
        require(place >= 0, "vote not for top three symbols");
        // reward claiming restriction based on timeliness of vote
        int128 timeliness = getVoteTimeliness(cycle, vote);
        if (
            (place == 1 && timeliness >= ABDKMath64x64.divu(2, 3)) ||
            (place == 2 && timeliness >= ABDKMath64x64.divu(1, 3))
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
        uint64 reward = ABDKMath64x64.toUInt(normalizedReward);
        (bool overflow, uint256 newCycleBalance) = cycle.balance.trySub(reward);
        if (overflow) {
            cycle.balance = 0;
        } else {
            cycle.balance = newCycleBalance;
        }
        vote.claimed = true;
        Address.sendValue(payable(msg.sender), reward);
        emit VoteClaimed(msg.sender, cycleId, vote.symbol, reward);
    }

    /**
     * @dev Retrieves the number of votes for a specific symbol in a cycle.
     * @param cycleId The cycle ID to query.
     * @param symbol The four-byte symbol to check for vote count.
     * @return voteCount The number of votes for the specified symbol.
     */
    function symbolVoteCount(
        uint256 cycleId,
        bytes4 symbol
    ) public view returns (uint) {
        return votesMeta[cycleId][symbol].length;
    }

    /**
     * @dev Retrieves the top three most voted symbols for a cycle.
     * @param cycleId The cycle ID to query.
     * @return first The most voted symbol.
     * @return second The second most voted symbol.
     * @return third The third most voted symbol.
     */
    function getTopThreeSymbols(
        uint256 cycleId
    )
        public
        view
        returns (string memory first, string memory second, string memory third)
    {
        require(cycles[cycleId].exists, "invalid cycle id");
        first = string(
            abi.encodePacked(symbols[cycleId].get(topThreeSymbols[cycleId][0]))
        );
        second = string(
            abi.encodePacked(symbols[cycleId].get(topThreeSymbols[cycleId][1]))
        );
        third = string(
            abi.encodePacked(symbols[cycleId].get(topThreeSymbols[cycleId][2]))
        );
    }

    /**
     * @dev Retrieves the total number of votes in a cycle.
     * @param cycleId The cycle ID to query.
     * @return totalVotes The total number of votes in the specified cycle.
     */
    function totalVoteCount(uint256 cycleId) public view returns (uint) {
        return cycles[cycleId].voteIdCounter;
    }

    /**
     * @dev Retrieves the current balance of the reward pool for a cycle.
     * @param cycleId The cycle ID to query.
     * @return balance The current balance of the reward pool.
     */
    function cycleRewardPoolBalance(
        uint256 cycleId
    ) public view returns (uint256) {
        return cycles[cycleId].balance;
    }
}
