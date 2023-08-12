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

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "forge-std/StdError.sol";

import "../src/Racer.sol" as Racer;

contract Racer2Test is Test {
    Racer.Racer market;

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

    function setUp() public {
        market = new Racer.Racer();
    }

    function testCreateCycle(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    ) public {
        vm.assume(votePrice > 0);

        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectEmit();
        emit CycleCreated(address(1), 0, startingBlock, blockLength, votePrice);
        market.createCycle(startingBlock, blockLength, votePrice);
        vm.stopPrank();
    }

    function testGetCycle(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    ) public {
        vm.assume(votePrice > 0);

        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        uint256 cycleId = market.createCycle(
            startingBlock,
            blockLength,
            votePrice
        );
        (
            uint256 startingBlock_,
            uint256 endingBlock_,
            uint256 votePrice_,
            address creator,
            uint256 balance,
            uint256 totalVotes
        ) = market.getCycle(cycleId);
        assertEq(startingBlock, startingBlock_);
        assertEq(startingBlock + blockLength, endingBlock_);
        assertEq(votePrice_, votePrice);
        assertEq(creator, address(1));
        assertEq(balance, 0);
        assertEq(totalVotes, 0);
        vm.stopPrank();
    }

    function testCreateCycleRevertsOnOverflow(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    ) public {
        vm.assume(votePrice > 0);
        // check for arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength < startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectRevert(stdError.arithmeticError);
        market.createCycle(startingBlock, blockLength, votePrice);
        vm.stopPrank();
    }

    function testGetCycleRevertsOnNonExistentID(uint256 cycleId) public {
        vm.startPrank(address(1));
        vm.expectRevert("cycle doesn't exist");
        market.getCycle(cycleId);
        vm.stopPrank();
    }

    function testCreateCycleRevertsOnZeroVotePrice(
        uint256 startingBlock,
        uint256 blockLength
    ) public {
        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectRevert("vote price must be greater than 0");
        market.createCycle(startingBlock, blockLength, 0);
        vm.stopPrank();
    }

    function testPlaceVote(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        bytes4 symbol
    ) public {
        vm.assume(blockLength > 0);
        testCreateCycle(startingBlock, blockLength, votePrice);
        vm.deal(address(1), votePrice);
        vm.startPrank(address(1));
        vm.roll(startingBlock);
        vm.expectEmit();
        emit VotePlaced(address(1), 0, 0, symbol);
        market.placeVote{value: votePrice}(0, symbol);
        assertEqUint(market.totalVoteCount(0), 1);
        assertEqUint(market.cycleRewardPoolBalance(0), votePrice);
        assertEqUint(market.symbolVoteCount(0, symbol), 1);
        vm.stopPrank();
    }

    function testPlaceVoteAfterCycleEnds(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        bytes4 symbol
    ) public {
        vm.assume(blockLength > 0);
        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength < UINT256_MAX - 2);
        }
        testCreateCycle(startingBlock, blockLength, votePrice);
        vm.deal(address(1), votePrice);
        vm.startPrank(address(1));
        vm.roll(startingBlock + blockLength + 1);
        vm.expectRevert("voting is unavailable");
        market.placeVote{value: votePrice}(0, symbol);
        vm.stopPrank();
    }

    function testPlaceVoteBeforeCycleStarts(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        bytes4 symbol
    ) public {
        vm.assume(blockLength > 0);
        vm.assume(startingBlock > 1);
        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength < UINT256_MAX);
        }
        testCreateCycle(startingBlock, blockLength, votePrice);
        vm.deal(address(1), votePrice);
        vm.startPrank(address(1));
        vm.roll(startingBlock - 1);
        vm.expectRevert("voting is unavailable");
        market.placeVote{value: votePrice}(0, symbol);
        vm.stopPrank();
    }

    function testPlaceVoteWithIncorrectPrice(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        bytes4 symbol
    ) public {
        vm.assume(blockLength > 0);
        testCreateCycle(startingBlock, blockLength, votePrice);
        vm.deal(address(1), votePrice);
        vm.startPrank(address(1));
        vm.roll(startingBlock);
        vm.expectRevert("incorrect wei amount for this cycle");
        market.placeVote{value: votePrice - 1}(0, symbol);
        vm.stopPrank();
    }

    function testPlaceVote1() public {
        uint256[] memory aliceVotes = new uint256[](2);
        uint256[] memory bobVotes = new uint256[](3);
        uint256[] memory johnVotes = new uint256[](2);

        address god = address(1);
        address alice = address(2);
        address bob = address(3);
        address john = address(4);

        vm.deal(alice, 2 ether);
        vm.deal(bob, 3 ether);
        vm.deal(john, 2 ether);

        vm.prank(god);
        uint256 cycleId = market.createCycle(0, 10, 1e18);

        vm.prank(alice);
        aliceVotes[0] = market.placeVote{value: 1e18}(cycleId, "AAPL");

        vm.prank(john);
        johnVotes[0] = market.placeVote{value: 1e18}(cycleId, "GOOG");

        vm.roll(2);
        vm.prank(alice);
        aliceVotes[1] = market.placeVote{value: 1e18}(cycleId, "AAPL");

        vm.startPrank(bob);
        vm.roll(4);
        bobVotes[0] = market.placeVote{value: 1e18}(cycleId, "AAPL");
        vm.roll(6);
        bobVotes[1] = market.placeVote{value: 1e18}(cycleId, "AAPL");
        vm.roll(8);
        bobVotes[2] = market.placeVote{value: 1e18}(cycleId, "AAPL");
        vm.stopPrank();

        vm.prank(john);
        johnVotes[1] = market.placeVote{value: 1e18}(cycleId, "GOOG");

        assertEq(market.totalVoteCount(cycleId), 7);
        assertEq(market.cycleRewardPoolBalance(cycleId), 7e18);

        vm.roll(11);
        vm.startPrank(alice);
        for (uint256 i = 0; i < aliceVotes.length; i++) {
            console.log(
                "[Alice] Claiming reward for vote id: %d",
                aliceVotes[i]
            );
            market.claimReward(cycleId, aliceVotes[i]);
        }
        vm.stopPrank();

        vm.startPrank(bob);
        for (uint256 i = 0; i < bobVotes.length; i++) {
            console.log("[Bob] Claiming reward for vote id: %d", bobVotes[i]);
            market.claimReward(cycleId, bobVotes[i]);
        }
        vm.stopPrank();

        vm.startPrank(john);
        for (uint256 i = 0; i < johnVotes.length - 1; i++) {
            console.log("[John] Claiming reward for vote id: %d", johnVotes[i]);
            market.claimReward(cycleId, johnVotes[i]);
        }

        // test late vote
        // mustn't be claimed
        uint256 lateVoteId = johnVotes[johnVotes.length - 1];
        vm.expectRevert();
        market.claimReward(cycleId, lateVoteId);
        vm.stopPrank();

        // should be claimed
        vm.startPrank(god);
        market.claimReward(cycleId, lateVoteId);
        vm.stopPrank();

        console.log("Alice's balance: ", alice.balance);
        console.log("Bob's balance: ", bob.balance);
        console.log("John's balance: ", john.balance);
        console.log("God's balance: ", god.balance);
        console.log(
            "Reward pool balance: ",
            market.cycleRewardPoolBalance(cycleId)
        );
    }
}
