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
        vm.stopPrank();
    }

    function testPlaceVoteInInvalidBlockNumber(
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
        vm.roll(startingBlock+blockLength+1);
        vm.expectRevert("voting is unavailable");
        market.placeVote{value: votePrice}(0, symbol);
        vm.stopPrank();
    }
}
