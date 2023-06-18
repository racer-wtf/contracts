// SPDX-License-Identifier: MIT

//  @
//   )
//  ( _m_
//   \ " /,~~.
//    `(''/.\)
//     .>' (_--,
//  _=/d  . ^\
// ~' \)-'   '
//   // |'
pragma solidity ^0.8.20;

import "../lib/abdk-libraries-solidity/ABDKMath64x64.sol";

contract Racer {
    using ABDKMath64x64 for int128;

    // The cycle's vote price must be greater than zero
    error VotePriceZero();
    // No ether was provided to the function
    error NoEtherProvided();
    // The number of votes must be a multiple of cycle.votePrice
    error InvalidNumberOfVotes();
    // The cycle already ended and the operation can't be performed
    error CycleEnded();
    // The cycle hasn't ended yet
    error CycleNotEnded();
    // The vote was already claimed
    error AlreadyClaimed();

    // Value of 2 in 64.64 fixed point
    int128 private constant TWO_64x64 = 0x20000000000000000;
    // Value of 3 in 64.64 fixed point
    int128 private constant THREE_64x64 = 0x30000000000000000;

    struct Vote {
        // four byte symbol of the vote
        bytes4 symbol;
        // amount of votes the player wants to place
        uint56 amount;
        // the address that placed the vote
        address placer;
        // represents if the reward was claimed or not
        bool claimed;
        // the cycle the vote belongs to
        uint256 cycle;
        // the amount of votes that came before
        uint256 placement;
    }

    struct Cycle {
        // the current cycle's starting block
        uint256 startingBlock;
        // amount of blocks the cycle will run for
        uint256 endingBlock;
        // the cost of one vote in wei
        uint256 votePrice;
        // the reward multiplier for the cycle
        uint256 multiplier;
        // the address of the cycle creator
        address creator;
    }

    // list of all cycles
    Cycle[] public cycles;
    // cycle index => symbol => votes[]
    mapping(uint256 => mapping(bytes4 => Vote[])) public votes;
    // cycle index => the top 3 symbols by vote count
    mapping(uint256 => bytes4[3]) public topThree;
    // cycle index => total votes
    mapping(uint256 => uint256) public totalVotes;
    // cycle index => total cycle balance
    mapping(uint256 => uint256) public cycleBalances;
    // cycle index => vote symbol => total symbol votes
    mapping(uint256 => mapping(bytes4 => uint256)) public symbolVotes;
    // cycle index => vote symbols
    mapping(uint256 => bytes4[]) public symbols;

    event CycleCreated(
        address indexed creator,
        uint256 indexed id,
        uint256,
        uint256,
        uint256
    );

    event VotePlaced(
        address indexed placer,
        uint256 indexed voteId,
        uint256 indexed cycleId,
        bytes4 symbol,
        uint256 amount,
        uint256 placement
    );

    event VoteClaimed(
        address indexed placer,
        uint256 indexed cycleId,
        bytes4 indexed symbol,
        uint256 amount
    );

    // Creates a cycle
    // @notice anyone can create a cycle
    function createCycle(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        uint256 multiplier
    ) public returns (uint256 cycleId) {
        if (votePrice == 0) {
            revert VotePriceZero();
        }

        cycleId = cycles.length;
        Cycle storage cycle = cycles.push();
        cycle.startingBlock = startingBlock;
        cycle.endingBlock = startingBlock + blockLength;
        cycle.votePrice = votePrice;
        cycle.multiplier = multiplier;
        cycle.creator = msg.sender;

        emit CycleCreated(
            msg.sender,
            cycleId,
            startingBlock,
            blockLength,
            votePrice
        );
    }

    // Gets information for a cycle
    function getCycle(
        uint256 cycleId
    )
        public
        view
        returns (uint256, uint256, uint256, uint256, address, uint256, uint256)
    {
        return (
            cycles[cycleId].startingBlock,
            cycles[cycleId].endingBlock,
            cycles[cycleId].votePrice,
            cycles[cycleId].multiplier,
            cycles[cycleId].creator,
            totalVotes[cycleId],
            cycleBalances[cycleId]
        );
    }

    // Places votes based on how much wei was sent
    function placeVote(
        uint256 cycleId,
        bytes4 symbol
    ) public payable returns (uint256 voteId) {
        Cycle storage cycle = cycles[cycleId];

        if (msg.value == 0) {
            revert NoEtherProvided();
        }
        if (msg.value % cycle.votePrice != 0) {
            revert InvalidNumberOfVotes();
        }
        if (block.number > cycle.endingBlock) {
            revert CycleEnded();
        }

        uint256 amount = msg.value / cycle.votePrice;
        uint256 placement = symbolVotes[cycleId][symbol] + 1;

        // create vote
        voteId = votes[cycleId][symbol].length;
        Vote memory vote = votes[cycleId][symbol].push();
        vote = Vote(
            symbol,
            uint56(amount),
            msg.sender,
            false,
            cycleId,
            placement
        );

        // add to cycle
        totalVotes[cycleId] += amount;
        cycleBalances[cycleId] += msg.value;
        symbolVotes[cycleId][symbol] += amount;

        // update the top three symbols
        updateTopThree(cycleId, symbol);

        emit VotePlaced(msg.sender, voteId, cycleId, symbol, amount, placement);
    }

    function updateTopThree(uint256 cycleId) internal {
        // TODO this funciton is not doing what its supposed to do lol
        // use the `symbols` variable to iterate over each symbol and
        // then update the top three
        uint256 voteCount = symbolVotes[cycleId][symbol];

        // store a reference to avoid multiple storage reads
        bytes4[3] storage currentTopThree = topThree[cycleId];

        if (voteCount > symbolVotes[cycleId][currentTopThree[0]]) {
            currentTopThree[2] = currentTopThree[1];
            currentTopThree[1] = currentTopThree[0];
            currentTopThree[0] = symbol;
        } else if (voteCount > symbolVotes[cycleId][currentTopThree[1]]) {
            currentTopThree[2] = currentTopThree[1];
            currentTopThree[1] = symbol;
        } else if (voteCount > symbolVotes[cycleId][currentTopThree[2]]) {
            currentTopThree[2] = symbol;
        }
    }

    function calculateNormalizationFactor(
        uint256 cycleId
    ) public view returns (int128) {
        Cycle storage cycle = cycles[cycleId];

        // holds the total accumulated reward sum
        int128 sumReward;

        // calculate base reward
        int128 baseReward = ABDKMath64x64.divu(
            cycleBalances[cycleId],
            totalVotes[cycleId]
        );

        // calculate rewards for placement #1
        bytes4 firstPlace = topThree[cycleId][0];
        for (uint256 i = symbolVotes[cycleId][firstPlace]; i != 0; ) {
            // y = x ^ multiplier * baseReward
            int128 reward = ABDKMath64x64.fromUInt(i);
            reward = reward.pow(cycle.multiplier);
            reward = reward.mul(baseReward);
            sumReward = reward;
            --i;
        }

        // calculate rewards for placement #2
        bytes4 secondPlace = topThree[cycleId][1];
        for (uint256 i = symbolVotes[cycleId][secondPlace]; i != 0; ) {
            // y = (x / 2) ^ multiplier * baseReward
            int128 reward = ABDKMath64x64.fromUInt(i);
            reward = reward.div(TWO_64x64);
            reward = reward.pow(cycle.multiplier);
            reward = reward.mul(baseReward);
            sumReward = reward;
            --i;
        }

        // calculate rewards for placement #3
        bytes4 thirdPlace = topThree[cycleId][2];
        for (uint256 i = symbolVotes[cycleId][thirdPlace]; i != 0; ) {
            // y = (x / 3) ^ multiplier * baseReward
            int128 reward = ABDKMath64x64.fromUInt(i);
            reward = reward.div(THREE_64x64);
            reward = reward.pow(cycle.multiplier);
            reward = reward.mul(baseReward);
            sumReward = reward;
            --i;
        }

        uint256 sumRewardUint = ABDKMath64x64.toUInt(sumReward);
        sumReward = ABDKMath64x64.divu(cycleBalances[cycleId], sumRewardUint);
        return sumReward;
    }

    function calculateReward(
        uint256 cycleId,
        bytes4 symbol,
        uint256 voteId,
        int128 normalizationFactor
    ) public view returns (uint256) {
        Cycle storage cycle = cycles[cycleId];
        Vote storage vote = votes[cycleId][symbol][voteId];

        // calculate base reward
        int128 baseReward = ABDKMath64x64.divu(
            cycleBalances[cycleId],
            totalVotes[cycleId]
        );

        int128 reward;

        // calculate reward for placement #1
        if (vote.symbol == topThree[cycleId][0]) {
            for (
                uint256 i = vote.placement + vote.amount;
                i != vote.placement;

            ) {
                // y = x ^ multiplier * baseReward
                int128 x = ABDKMath64x64.fromUInt(i);
                x = x.pow(cycle.multiplier);
                x = x.mul(baseReward);
                reward += x;
                --i;
            }
        }
        // calculate reward for placement #2
        else if (vote.symbol == topThree[cycleId][1]) {
            uint256 secondPlaceCutoff = symbolVotes[cycleId][vote.symbol] / 2;
            for (
                uint256 i = vote.placement + vote.amount;
                i != vote.placement && i > secondPlaceCutoff;

            ) {
                // y = (x / 2) ^ multiplier * baseReward
                int128 x = ABDKMath64x64.fromUInt(i);
                x = x.div(TWO_64x64);
                x = x.pow(cycle.multiplier);
                x = x.mul(baseReward);
                reward += x;
                --i;
            }
        }
        // calculate reward for placement #3
        else if (vote.symbol == topThree[cycleId][2]) {
            uint256 thirdPlaceCutoff = symbolVotes[cycleId][vote.symbol] / 2;
            for (
                uint256 i = vote.placement + vote.amount;
                i != vote.placement && i > thirdPlaceCutoff;

            ) {
                // y = (x / 3) ^ multiplier * baseReward
                int128 x = ABDKMath64x64.fromUInt(i);
                x = x.div(THREE_64x64);
                x = x.pow(cycle.multiplier);
                x = x.mul(baseReward);
                reward += x;
                --i;
            }
        }

        reward = normalizationFactor.mul(reward);
        return ABDKMath64x64.toUInt(reward);
    }

    function claim(uint256 cycleId, uint256 voteId, bytes4 symbol) public {
        Cycle storage cycle = cycles[cycleId];
        Vote storage vote = votes[cycleId][symbol][voteId];

        if (block.number < cycle.endingBlock) {
            revert CycleNotEnded();
        }
        if (vote.claimed) {
            revert AlreadyClaimed();
        }

        // TODO: sort top3 here
        int128 normalizationFactor = calculateNormalizationFactor(cycleId);
        uint256 reward = calculateReward(
            cycleId,
            vote.symbol,
            vote.placement,
            normalizationFactor
        );

        vote.claimed = true;
        payable(msg.sender).transfer(reward);

        emit VoteClaimed(msg.sender, cycleId, vote.symbol, reward);
    }
}
