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
import {FoundryRandom} from "foundry-random/FoundryRandom.sol";

import "../src/Racer.sol" as Racer;

contract Racer2Test is Test, FoundryRandom {
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

    function randomString(uint size) internal returns (string memory) {
        bytes memory randomWord = new bytes(size);
        bytes memory chars = new bytes(26);
        chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        for (uint i = 0; i < size; i++) {
            uint randomNumber = randomNumber(25);
            randomWord[i] = chars[randomNumber];
        }
        return string(randomWord);
    }

    function convertBytesToBytes4(
        bytes memory inBytes
    ) internal pure returns (bytes4 outBytes4) {
        if (inBytes.length == 0) {
            return 0x0;
        }

        assembly {
            outBytes4 := mload(add(inBytes, 32))
        }
    }

    function testIntegrationPlaceVotes() public {
        uint256 blockLength = randomNumber(50, 100);
        address god = address(0);
        vm.prank(god);
        market.createCycle(0, blockLength, 1 ether);

        uint256 voterCount = randomNumber(50, 500);
        console.log("count of voters:", voterCount);
        uint256 symbolCount = randomNumber(5, 25);
        address[] memory voters = new address[](voterCount);
        bytes4[] memory symbols = new bytes4[](symbolCount);

        for (uint i = 0; i < symbolCount; i++) {
            symbols[i] = convertBytesToBytes4(
                abi.encodePacked(randomString(4))
            );
            // console.log(string(abi.encodePacked(symbols[i])));
        }
        for (uint160 i = 0; i < voterCount; i++) {
            voters[i] = address(10 + i);
        }

        uint256[][] memory votes = new uint256[][](voters.length);

        // place votes
        for (uint256 i = 0; i < voters.length; i++) {
            uint256 voteCount = randomNumber(10);
            votes[i] = new uint256[](voteCount);
            vm.deal(voters[i], (voteCount) * 10 ** 18);
            uint256 currentBlock = 0;
            vm.roll(0);
            vm.startPrank(voters[i]);
            for (uint256 j = 0; j < voteCount; j++) {
                currentBlock += randomNumber(blockLength / voteCount);
                vm.roll(currentBlock);
                bytes4 randomSymbol = symbols[randomNumber(symbols.length - 1)];
                votes[i][j] = market.placeVote{value: 1 ether}(0, randomSymbol);
            }
            vm.stopPrank();
        }

        console.log("reward pool:", market.cycleRewardPoolBalance(0));
        (
            string memory first,
            string memory second,
            string memory third
        ) = market.getTopThreeSymbols(0);
        console.log("first symbol:", first);
        console.log(
            market.symbolVoteCount(
                0,
                convertBytesToBytes4(abi.encodePacked(first))
            )
        );
        console.log("second symbol:", second);
        console.log(
            market.symbolVoteCount(
                0,
                convertBytesToBytes4(abi.encodePacked(second))
            )
        );
        console.log("third symbol:", third);
        console.log(
            market.symbolVoteCount(
                0,
                convertBytesToBytes4(abi.encodePacked(third))
            )
        );

        vm.roll(blockLength + 1);
        // claim vote rewards
        for (uint i = 0; i < voters.length; i++) {
            for (uint j = 0; j < votes[i].length; j++) {
                vm.startPrank(voters[i]);
                if (market.isClaimingRewardAvailable(0, votes[i][j])) {
                    market.claimReward(0, votes[i][j]);
                    vm.stopPrank();
                } else {
                    vm.stopPrank();
                    vm.startPrank(god);
                    if (market.isClaimingRewardAvailable(0, votes[i][j])) {
                        market.claimReward(0, votes[i][j]);
                    }
                    vm.stopPrank();
                }
            }
        }
        console.log(
            "reward pool when finished:",
            market.cycleRewardPoolBalance(0)
        );
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
