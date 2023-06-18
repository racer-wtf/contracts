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

import "../src/Racer.sol";

contract Racer2Test is Test {
    Racer market;

    function setUp() public {
        market = new Racer();
    }

    event CycleCreated(
        address indexed creator,
        uint256 indexed id,
        uint256,
        uint256,
        uint256
    );

    // tests that the createCycle function works and emits the correct event
    function testCreateCycleWorks(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        uint256 multiplier
    ) public {
        vm.assume(votePrice > 0);
        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectEmit(true, true, true, true, address(market));
        emit CycleCreated(address(1), 0, startingBlock, blockLength, votePrice);
        market.createCycle(startingBlock, blockLength, votePrice, multiplier);
        vm.stopPrank();
    }

    function testCreateCycleRevertsOn0VotePrice(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 multiplier
    ) public {
        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Racer.VotePriceZero.selector));
        market.createCycle(startingBlock, blockLength, 0, multiplier);
        vm.stopPrank();
    }

    function testCreateCycleRevertsOnOverflow(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        uint256 multiplier
    ) public {
        vm.assume(votePrice > 0);
        // check for arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength < startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectRevert(stdError.arithmeticError);
        market.createCycle(startingBlock, blockLength, votePrice, multiplier);
        vm.stopPrank();
    }

    function testGetCycleWorks(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        uint256 multiplier
    ) public {
        vm.assume(votePrice > 0);
        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        market.createCycle(startingBlock, blockLength, votePrice, multiplier);
        (
            uint256 startingBlock2,
            uint256 endingBlock,
            uint256 votePrice2,
            uint256 multiplier2,
            address creator,
            uint256 totalVotes,
            uint256 cycleBalances
        ) = market.getCycle(0);
        assertEq(startingBlock2, startingBlock);
        assertEq(endingBlock, startingBlock + blockLength);
        assertEq(votePrice2, votePrice);
        assertEq(multiplier2, multiplier);
        assertEq(creator, address(1));
        assertEq(totalVotes, 0);
        assertEq(cycleBalances, 0);
        vm.stopPrank();
    }

    function testGetCycleOutOfBoundsReverts(uint256 id) public {
        vm.startPrank(address(1));
        vm.expectRevert(stdError.indexOOBError);
        market.getCycle(id);
        vm.stopPrank();
    }

    event VotePlaced(
        address indexed placer,
        uint256 indexed voteId,
        uint256 indexed cycleId,
        bytes4 symbol,
        uint256 amount,
        uint256 placement
    );

    function testPlaceVoteWorks(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice,
        uint256 multiplier,
        bytes4 symbol
    ) public {
        vm.assume(blockLength > 0);
        testCreateCycleWorks(startingBlock, blockLength, votePrice, multiplier);

        vm.deal(address(1), votePrice);
        vm.startPrank(address(1));
        vm.expectEmit(true, true, true, true, address(market));
        emit VotePlaced(address(1), 0, 0, symbol, 1, 1);
        market.placeVote{value: votePrice}(0, symbol);
        vm.stopPrank();
    }
}
