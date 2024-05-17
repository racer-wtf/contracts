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

    // State variables

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

    // Events

    event CycleCreated(
        address indexed creator,
        uint256 indexed id,
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    );

    event VotePlaced(
        address indexed placer,
        uint256 indexed voteId,
        uint256 indexed cycleId,
        bytes4 symbol
    );

    event VoteClaimed(
        uint256 indexed cycleId,
        uint256 indexed voteId,
        address indexed claimer,
        bytes4 symbol,
        uint256 amount
    );

    // Structs

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

    // Errors

    // @return cycleId The cycle ID for which the vote is placed.
    error CycleDoesntExist(uint256 cycleId);
    // @return cycleId The cycle ID for which the vote is placed.
    error CycleDidntEnd(uint256 cycleId);
    // @return cycleId The cycle ID for which the vote is placed.
    error CycleVotingIsUnavailable(uint256 cycleId);
    // @return correctFee The correct fee for the vote.
    error InvalidVoteFee(uint256 correctFee);
    // @dev When the vote price is 0 this is returned.
    error InvalidVotePrice();
    // @dev When the vote is already claimed this is returned.
    error VoteAlreadyClaimed();
    // @return voteId The unique identifier for the vote.
    error VoteDoesntExist(uint256 voteId);
    // @return voteId The unique identifier for the vote.
    error VoteDidntPlace(uint256 voteId);
    // @return voteId The unique identifier for the vote.
    // @return caller The address of the caller.
    error VoteNotPlacedByCaller(uint256 voteId, address caller);

    // Public functions

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
        if (!cycles[cycleId].exists) revert CycleDoesntExist(cycleId);
        if (
            cycles[cycleId].startingBlock > block.number ||
            cycles[cycleId].endingBlock < block.number
        ) revert CycleVotingIsUnavailable(cycleId);
        if (msg.value != cycles[cycleId].votePrice) {
            revert InvalidVoteFee(cycles[cycleId].votePrice);
        }

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
        unchecked {
            cycle.balance += cycle.votePrice;
        }

        updateTopThreeSymbols(cycleId);

        emit VotePlaced(msg.sender, voteId, cycleId, symbol);
        return voteId;
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
        if (votePrice == 0) revert InvalidVotePrice();

        uint256 cycleId = cycleIdCounter++;
        cycles[cycleId] = Cycle(
            cycleId,
            startingBlock,
            startingBlock + blockLength,
            votePrice,
            msg.sender,
            0,
            true,
            0
        );

        emit CycleCreated(
            msg.sender,
            cycleId,
            startingBlock,
            blockLength,
            votePrice
        );
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
        if (!cycle.exists) revert CycleDoesntExist(cycleId);
        startingBlock = cycle.startingBlock;
        endingBlock = cycle.endingBlock;
        votePrice = cycle.votePrice;
        creator = cycle.creator;
        balance = cycle.balance;
        for (uint256 i = 0; i < symbols[cycleId].count(); ) {
            unchecked {
                totalVotes += votesMeta[cycleId][symbols[cycleId].get(i)]
                    .length;
                i++;
            }
        }
    }

    /**
     * @dev Calculates the normalized factor for a cycle, which is used to calculate rewards.
     * @notice This function is very gas-costly and should be called only once per cycle.
     * @param cycle The cycle struct to calculate the normalized factor for.
     * @return normalizationFactor The calculated normalization factor.
     */
    function calculateNormalizedFactor(
        Cycle storage cycle
    ) internal view returns (int128) {
        int128 normalizationFactor = 0;

        // summing points from the first symbol
        bytes4 firstSymbol = symbols[cycle.id].get(
            topThreeSymbols[cycle.id][0]
        );
        uint256[] storage firstSymbolVotes = votesMeta[cycle.id][firstSymbol];
        for (uint256 i = 0; i < firstSymbolVotes.length; ) {
            Vote storage vote = votes[cycle.id][
                votesMeta[cycle.id][firstSymbol][i]
            ];
            int128 rewardPoint = calculatePoint(cycle, vote, 0);
            normalizationFactor = ABDKMath64x64.add(
                normalizationFactor,
                rewardPoint
            );
            unchecked {
                i++;
            }
        }

        if (topThreeSymbols[cycle.id][0] != topThreeSymbols[cycle.id][1]) {
            // summing points from the second symbol
            bytes4 secondSymbol = symbols[cycle.id].get(
                topThreeSymbols[cycle.id][1]
            );
            uint256[] storage secondSymbolVotes = votesMeta[cycle.id][
                secondSymbol
            ];
            for (uint256 i = 0; i < secondSymbolVotes.length; ) {
                Vote storage vote = votes[cycle.id][
                    votesMeta[cycle.id][secondSymbol][i]
                ];
                int128 rewardPoint = calculatePoint(cycle, vote, 1);
                normalizationFactor = ABDKMath64x64.add(
                    normalizationFactor,
                    rewardPoint
                );
                unchecked {
                    i++;
                }
            }
        }

        if (topThreeSymbols[cycle.id][0] != topThreeSymbols[cycle.id][2]) {
            // summing points from the third symbol
            bytes4 thirdSymbol = symbols[cycle.id].get(
                topThreeSymbols[cycle.id][2]
            );
            uint256[] storage thirdSymbolVotes = votesMeta[cycle.id][
                thirdSymbol
            ];
            for (uint256 i = 0; i < thirdSymbolVotes.length; ) {
                Vote storage vote = votes[cycle.id][
                    votesMeta[cycle.id][thirdSymbol][i]
                ];
                int128 rewardPoint = calculatePoint(cycle, vote, 2);
                normalizationFactor = ABDKMath64x64.add(
                    normalizationFactor,
                    rewardPoint
                );
                unchecked {
                    i++;
                }
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
     * @dev Calculates the normalized reward for a vote within a cycle.
     * @param cycleId The cycle ID the vote belongs to.
     * @param voteId The unique identifier for the vote.
     * @return normalizedReward The calculated normalized reward for the vote.
     */
    function calculateReward(
        uint256 cycleId,
        uint256 voteId
    ) public view returns (int128) {
        if (!cycles[cycleId].exists) revert CycleDoesntExist(cycleId);
        if (!votes[cycleId][voteId].exists) revert VoteDoesntExist(voteId);
        Cycle storage cycle = cycles[cycleId];
        Vote storage vote = votes[cycleId][voteId];

        int128 normalizationFactor = calculateNormalizedFactor(cycle);
        int128 baseReward = getBaseReward(cycle);

        int256 place = getVotePlace(cycle, vote);
        if (place == -1) revert VoteDidntPlace(voteId);

        int128 curvePoint = calculatePoint(cycle, vote, uint(place));
        int128 normalizedReward = ABDKMath64x64.mul(
            ABDKMath64x64.mul(baseReward, curvePoint),
            normalizationFactor
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
        if (!cycle.exists) revert CycleDoesntExist(cycleId);
        if (block.number <= cycle.endingBlock) return false;
        Vote storage vote = votes[cycleId][voteId];
        if (!vote.exists) revert VoteDoesntExist(voteId);

        int256 place = getVotePlace(cycle, vote);
        if (place == -1) return false;
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
    function _claimReward(uint256 cycleId, uint256 voteId) internal {
        Cycle storage cycle = cycles[cycleId];
        if (!cycle.exists) revert CycleDoesntExist(cycleId);
        if (block.number <= cycle.endingBlock) revert CycleDidntEnd(cycleId);
        Vote storage vote = votes[cycleId][voteId];
        if (!vote.exists) revert VoteDoesntExist(voteId);
        if (vote.claimed) revert VoteAlreadyClaimed();

        int256 place = getVotePlace(cycle, vote);
        if (place == -1) revert VoteDidntPlace(voteId);
        // reward claiming restriction based on timeliness of vote
        int128 timeliness = getVoteTimeliness(cycle, vote);
        if (
            (place == 1 && timeliness >= ABDKMath64x64.divu(2, 3)) ||
            (place == 2 && timeliness >= ABDKMath64x64.divu(1, 3))
        ) {
            if (msg.sender != cycle.creator) revert VoteDidntPlace(voteId);
        } else {
            if (msg.sender != vote.placer)
                revert VoteNotPlacedByCaller(voteId, msg.sender);
        }

        int128 normalizedReward = calculateReward(cycleId, voteId);
        uint64 reward = ABDKMath64x64.toUInt(normalizedReward);
        vote.claimed = true;
        Address.sendValue(payable(msg.sender), reward);
        emit VoteClaimed(cycleId, voteId, msg.sender, vote.symbol, reward);
    }

    function batchClaimReward(
        uint256 cycleId,
        uint256[] calldata voteIds
    ) public nonReentrant {
        for (uint256 i = 0; i < voteIds.length; i++) {
            _claimReward(cycleId, voteIds[i]);
        }
    }

    function claimReward(uint256 cycleId, uint256 voteId) public nonReentrant {
        _claimReward(cycleId, voteId);
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
        if (!cycles[cycleId].exists) revert CycleDoesntExist(cycleId);
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

    // Internal function

    /**
     * @dev Updates the top three most voted symbols for a cycle.
     * @param cycleId The cycle ID to update the top symbols for.
     */
    function updateTopThreeSymbols(uint256 cycleId) internal {
        Symbol memory first = Symbol("", 0, 0);
        Symbol memory second = Symbol("", 0, 0);
        Symbol memory third = Symbol("", 0, 0);
        for (uint256 i = 0; i < symbols[cycleId].count(); ) {
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
            unchecked {
                i++;
            }
        }

        topThreeSymbols[cycleId][0] = first.pointer;
        topThreeSymbols[cycleId][1] = second.pointer;
        topThreeSymbols[cycleId][2] = third.pointer;
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
        uint256 place
    ) internal view returns (int128) {
        if (place < 0 || place > 2) revert VoteDidntPlace(vote.voteId);
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
    ) internal view returns (int256) {
        int256 place = -1;
        for (uint256 i = 0; i < 3; i++) {
            bytes4 symbol = symbols[cycle.id].get(topThreeSymbols[cycle.id][i]);
            if (symbol == vote.symbol) {
                place = int256(i);
                break;
            }
        }
        return place;
    }
}
