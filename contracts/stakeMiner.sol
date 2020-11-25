pragma solidity =0.6.12;

import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";


interface IStakeMiner {
    // charge reward token to contract
    function charge() external;
    // stake token for miner
    function deposit(uint256 _amount) external;
    // withdraw token to leave contract
    function withdraw(uint256 _amount) external;
    // stake EIP712 token for miner.
    function depositWithPermit(uint256 _amount,uint8 v, bytes32 r, bytes32 s, uint deadline) external;


    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

}

interface IERC712 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}


contract StakeMiner is IStakeMiner{

    using SafeMath for uint256;
    // per block reward token number
    uint256 public rewardTokenPerBlock;
    // stake token address
    address public stakeToken;
    // reward token address
    address public rewardToken;
    // Start block number
    uint256 public startBlock;
    // End block number
    uint256 public endBlock;


    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 reward; // how many reward the user has get.
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 lastRewardBlock;  // Last block number that token distribution occurs.
        uint256 accTokenPerShare; // Accumulated tokens per share, times 1e12. See below.
    }

    PoolInfo public poolInfo;
    // Info of each user that stakes  tokens.
    mapping (address => UserInfo) public userInfo;


    constructor(
        address _stakeToken,
        address _rewardToken,
        uint256 _rewardTokenPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
        rewardTokenPerBlock = _rewardTokenPerBlock;
        endBlock = _endBlock;
        startBlock = _startBlock;

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo = PoolInfo({
        lastRewardBlock: lastRewardBlock,
        accTokenPerShare: 0
        });
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= endBlock) {
            return _to.sub(_from);
        } else if (_from >= endBlock) {
            return 0;
        } else {
            return endBlock.sub(_from);
        }
    }

    function updatePool() private {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }
        uint256 tokenSupply = IERC20(stakeToken).balanceOf(address(this));
        if(tokenSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
        }

        uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
        uint256 reward = multiplier.mul(rewardTokenPerBlock);
        poolInfo.accTokenPerShare = poolInfo.accTokenPerShare.add(reward.mul(1e12).div(tokenSupply));
        poolInfo.lastRewardBlock = block.number;
    }

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user =  userInfo[_user];
        uint256 accTokenPerShare = poolInfo.accTokenPerShare;
        uint256 tokenSupply = IERC20(stakeToken).balanceOf(address(this));

        if(block.number > poolInfo.lastRewardBlock && tokenSupply != 0) {
            uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock,block.number);
            uint256 reward = multiplier.mul(rewardTokenPerBlock);
            accTokenPerShare = accTokenPerShare.add(reward.mul(1e12).div(tokenSupply));
        }

        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Deposit tokens for Token allocation.
    function deposit(uint256 _amount) external override {
        UserInfo storage user =  userInfo[msg.sender];
        updatePool();

        uint256 pending = 0;
        if(user.amount > 0) {
            pending = user.amount.mul(poolInfo.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            TransferHelper.safeTransfer(rewardToken,msg.sender,pending);
        }

        TransferHelper.safeTransferFrom(stakeToken,msg.sender,address(this),_amount);
        user.amount = user.amount.add(_amount);
        user.reward = user.reward.add(pending);
        user.rewardDebt = user.amount.mul(poolInfo.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _amount);
    }

    function depositWithPermit(uint256 _amount,uint8 v, bytes32 r, bytes32 s, uint deadline) external override {

        IERC712(stakeToken).permit(msg.sender, address(this), _amount, deadline, v, r, s);

        UserInfo storage user =  userInfo[msg.sender];
        updatePool();

        uint256 pending = 0;
        if(user.amount > 0) {
            pending = user.amount.mul(poolInfo.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            TransferHelper.safeTransfer(rewardToken,msg.sender,pending);
        }

        TransferHelper.safeTransferFrom(stakeToken,msg.sender,address(this),_amount);
        user.amount = user.amount.add(_amount);
        user.reward = user.reward.add(pending);
        user.rewardDebt = user.amount.mul(poolInfo.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw  tokens from StakeMiner.
    function withdraw(uint256 _amount) external override {
        UserInfo storage user =  userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();

        uint256 pending = user.amount.mul(poolInfo.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        TransferHelper.safeTransfer(rewardToken,msg.sender,pending);

        user.amount = user.amount.sub(_amount);
        user.reward = user.reward.add(pending);
        user.rewardDebt = user.amount.mul(poolInfo.accTokenPerShare).div(1e12);
        TransferHelper.safeTransfer(stakeToken,msg.sender,_amount);
        emit Withdraw(msg.sender, _amount);
    }

    function charge() external override {
        uint256 totalRewardToken = (endBlock.sub(startBlock)).mul(rewardTokenPerBlock);
        TransferHelper.safeTransferFrom(rewardToken,msg.sender,address(this),totalRewardToken);
    }
}


