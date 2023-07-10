// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/abdk-libraries-solidity/ABDKMath64x64.sol";

contract Racer {
    using ABDKMath64x64 for int128;

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
        uint256 voteIdCounter;
        // flag for checking existance of cycle
        bool exists;
    }

    event VotePlaced(
        address indexed placer,
        uint256 voteId,
        uint256 indexed cycleId,
        bytes4 indexed symbol,
        uint256 amount
    );

    // cycle id -> symbol -> votes array
    mapping (uint256 => mapping(bytes4 => uint256[])) votesMeta;
    
    // cycle id -> cycle
    mapping (uint256 => Cycle) cycles;

    // cycle id -> vote id -> vote
    mapping(uint256 => mapping(uint256 => Vote)) votes;

    constructor() {}

    // Places votes based on how much wei was sent
    function placeVote(
        uint256 cycleId,
        bytes4 symbol
    ) public payable returns (uint256) {
        require(cycles[cycleId].exists, "cycle doesn't exist");
        require(cycles[cycleId].startingBlock <= block.number, "cycle hasn't started yet");
        uint256 amount = msg.value;
        require(amount >= cycles[cycleId].votePrice, "paid amount is not enough for this cycle");
        uint256 voteId = cycles[cycleId].voteIdCounter;
        voteId++;
        cycles[cycleId].voteIdCounter = voteId;
        votes[cycleId][voteId] = Vote(voteId, symbol, amount, msg.sender, false, cycleId, block.number);
        votesMeta[cycleId][symbol].push(voteId);
        emit VotePlaced(msg.sender, voteId, cycleId, symbol, amount);
        uint256 refundAmount = amount - cycles[cycleId].votePrice;
        if (refundAmount > 0) {
            assert(payable(msg.sender).send(refundAmount));
        }
        return voteId;
    }
}
