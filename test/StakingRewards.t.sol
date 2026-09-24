// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../src/ERC20.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

contract StakingRewardsTest is Test {
    ERC20 internal stakeToken;
    ERC20 internal rewardToken;
    StakingRewards internal pool;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant DURATION = 1000;

    function setUp() public {
        stakeToken = new ERC20("Stake", "STK", 18);
        rewardToken = new ERC20("Reward", "RWD", 18);
        pool = new StakingRewards(address(stakeToken), address(rewardToken));

        stakeToken.mint(alice, 1_000e18);
        stakeToken.mint(bob, 1_000e18);
        rewardToken.mint(address(this), 1_000e18);

        vm.prank(alice);
        stakeToken.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        stakeToken.approve(address(pool), type(uint256).max);
        rewardToken.approve(address(pool), type(uint256).max);
    }

    function _fund(uint256 reward) internal {
        pool.notifyRewardAmount(reward, DURATION);
    }

    function test_StakeAndWithdraw() public {
        vm.prank(alice);
        pool.stake(100e18);
        assertEq(pool.balanceOf(alice), 100e18);
        assertEq(pool.totalSupply(), 100e18);

        vm.prank(alice);
        pool.withdraw(40e18);
        assertEq(pool.balanceOf(alice), 60e18);
        assertEq(stakeToken.balanceOf(alice), 940e18);
    }

    function test_SoleStakerEarnsTheWholeRate() public {
        _fund(1_000e18);
        vm.prank(alice);
        pool.stake(100e18);
        vm.warp(block.timestamp + 500);
        // 1000e18 over 1000s = 1e18/s, alice is the only staker
        assertApproxEqRel(pool.earned(alice), 500e18, 0.001e18);
    }

    function test_TwoStakersSplitProportionally() public {
        _fund(1_000e18);
        vm.prank(alice);
        pool.stake(100e18);
        vm.prank(bob);
        pool.stake(300e18);
        vm.warp(block.timestamp + 1000);
        uint256 a = pool.earned(alice);
        uint256 b = pool.earned(bob);
        // alice has a quarter of the stake, so roughly a third of bob's rewards
        assertApproxEqRel(b, a * 3, 0.01e18);
    }

    function test_GetRewardPaysOut() public {
        _fund(1_000e18);
        vm.prank(alice);
        pool.stake(100e18);
        vm.warp(block.timestamp + 1000);
        vm.prank(alice);
        pool.getReward();
        assertGt(rewardToken.balanceOf(alice), 0);
        assertEq(pool.rewards(alice), 0);
    }

    function test_ExitReturnsStakeAndRewards() public {
        _fund(1_000e18);
        vm.prank(alice);
        pool.stake(100e18);
        vm.warp(block.timestamp + 1000);
        vm.prank(alice);
        pool.exit();
        assertEq(pool.balanceOf(alice), 0);
        assertEq(stakeToken.balanceOf(alice), 1_000e18);
        assertGt(rewardToken.balanceOf(alice), 0);
    }

    function test_CannotWithdrawMoreThanStaked() public {
        vm.prank(alice);
        pool.stake(10e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StakingRewards.InsufficientStake.selector, 10e18, 11e18));
        pool.withdraw(11e18);
    }

    function test_OnlyOwnerCanFund() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.OnlyOwner.selector);
        pool.notifyRewardAmount(1e18, DURATION);
    }

    function test_NoRewardsBeforeFunding() public {
        vm.prank(alice);
        pool.stake(100e18);
        vm.warp(block.timestamp + 1000);
        assertEq(pool.earned(alice), 0);
    }
}
