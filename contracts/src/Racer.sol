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
        // amount of votes the player wants to place
        uint256 amount;
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
        // vote id counter for this cycle
        Counters.Counter voteIdCounter;
        // flag for checking existance of cycle
        bool exists;
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

    // cycle id -> symbol -> votes array
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
            "incorrect amount for this cycle"
        );
        Cycle storage cycle = cycles[cycleId];
        cycle.voteIdCounter.increment();
        uint256 voteId = cycle.voteIdCounter.current();
        votes[cycleId][voteId] = Vote(
            voteId,
            symbol,
            amount,
            msg.sender,
            false,
            cycleId,
            block.number
        );
        votesMeta[cycleId][symbol].push(voteId);
        if(!symbols[cycleId].exists(symbol)) {
            symbols[cycleId].insert(symbol);
        }

        updateTopThreeSymbols(cycleId);

        emit VotePlaced(msg.sender, voteId, cycleId, symbol, amount);
        return voteId;
    }

    // update top three most voted symbols
    function updateTopThreeSymbols(uint256 cycleId) {
        bool memory init = topThreeSymbols[cycleId].length != 0;
        Symbol memory first = Symbol("", 0, 0);
        Symbol memory second = Symbol("", 0, 0);
        Symbol memory third = Symbol("", 0, 0);
        for (uint i = 0; i < symbols[cycleId].count(); i++) {
            bytes4 storage symbol = symbols[cycleId].get(i);
            uint256 memory voteCount = votesMeta[cycleId][symbol].length;
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
        uint256 votePrice,
        uint256 multiplier
    ) public returns (uint256) {
        cycleIdCounter.increment();

        uint256 cycleId = cycleIdCounter.current();
        cycles[cycleId] = Cycle(
            startingBlock,
            startingBlock + blockLength,
            votePrice,
            multiplier,
            msg.sender,
            Counters.Counter(0),
            true
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

    function calculateNormalizedFactor() public returns (uint256) {

    }
}
