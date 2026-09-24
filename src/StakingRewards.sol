// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Rewards distribution, in the shape of Synthetix's StakingRewards.
/// @notice Reward tokens accrue per second and are split across staked balances
///         proportionally. The trick that makes it O(1) per user is tracking a
///         cumulative reward-per-token and snapshotting it on every balance
///         change.
contract StakingRewards {
    error OnlyOwner();
    error ZeroAmount();
    error RewardPeriodActive();
    error InsufficientStake(uint256 staked, uint256 wanted);
    error TransferFailed();

    address public owner;
    address public immutable stakingToken;
    address public immutable rewardToken;

    uint256 public rewardRate; // reward tokens per second
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardAdded(uint256 reward, uint256 periodFinish);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address stakingToken_, address rewardToken_) {
        owner = msg.sender;
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Cumulative rewards earned per staked token, scaled by 1e18.
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        // caller must have approved this contract to pull stakingToken
        (bool ok, bytes memory data) = stakingToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        if (balanceOf[msg.sender] < amount) revert InsufficientStake(balanceOf[msg.sender], amount);
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        (bool ok, bytes memory data) =
            stakingToken.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) return;
        rewards[msg.sender] = 0;
        (bool ok, bytes memory data) =
            rewardToken.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
        emit RewardPaid(msg.sender, reward);
    }

    function exit() external {
        withdraw(balanceOf[msg.sender]);
        getReward();
    }

    /// @notice Fund a reward period starting now. Caller must have approved the
    ///         reward tokens; the contract pulls them up front, which is what
    ///         makes the per-second rate solvent.
    function notifyRewardAmount(uint256 reward, uint256 duration) external onlyOwner {
        if (block.timestamp < periodFinish) revert RewardPeriodActive();
        (bool ok, bytes memory data) = rewardToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), reward)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
        rewardRate = reward / duration;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward, periodFinish);
    }
}
