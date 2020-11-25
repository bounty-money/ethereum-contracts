/**
 *Submitted for verification at Etherscan.io on 2020-11-26
*/
pragma solidity 0.6.12;

import "./interfaces/IERC20.sol";
import "./Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";
import "./bmToken.sol";

interface IMigratorChef {
    // Perform LP token migration from legacy UniswapV2 to SushiSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // SushiSwap must mint EXACTLY the same amount of SushiSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Sushi. He can make Sushi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract BountyMoneyV1Miner is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 reward;
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accWagyuPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accWagyuPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that WAGYU distribution occurs.
        uint256 accBMPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
        uint256 lpAmountRestricted; // Restricted user lp amount
    }
    // The WAGYU TOKEN!
    BountyMoneyToken public bountyMoney;
    // Dev address.
    address public devaddr;
    // Block number when bonus SUSHI period ends.

    // bountyMoney tokens created per block.
    uint256 public bmPerBlock;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when WAGYU mining starts.
    uint256 public startBlock;
    // The block number when WAGYU mining end.
    uint256 public endBlock;
    // record token mint block
    uint256 public lastProduceBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Pool(address indexed lpToken,uint256 allocPoint,uint256 lpAmountRestricted);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        BountyMoneyToken _bountyMoney,
        address _devaddr,
        uint256 _bmPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public {
        bountyMoney = _bountyMoney;
        devaddr = _devaddr;
        bmPerBlock = _bmPerBlock;
        endBlock = _endBlock;
        startBlock = _startBlock;
        lastProduceBlock = startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate,uint256 _lpAmountRestricted) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accBMPerShare: 0,
        lpAmountRestricted: _lpAmountRestricted
        }));
        emit Pool(address(_lpToken),_allocPoint,_lpAmountRestricted);
    }

    // Update the given pool's WAGYU allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate,uint256 _lpAmountRestricted) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].lpAmountRestricted = _lpAmountRestricted;
        emit Pool(address(poolInfo[_pid].lpToken),_allocPoint,_lpAmountRestricted);
    }

    function transferTokenOwnership(address newOwner) public onlyOwner {
        bountyMoney.transferOwnership(newOwner);
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
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

    // View function to see pending WAGYU on frontend.
    function pendingBM(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBMPerShare = pool.accBMPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 bmReward = multiplier.mul(bmPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBMPerShare = accBMPerShare.add(bmReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accBMPerShare).div(1e12).sub(user.rewardDebt);
        if(user.amount > pool.lpAmountRestricted) {
            uint256 difLpAmount = user.amount.sub(pool.lpAmountRestricted);
            uint256 burnAmount = pending.div(user.amount).mul(difLpAmount);
            pending = pending.sub(burnAmount);
        }
        return pending;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        if(block.number > lastProduceBlock && lastProduceBlock < endBlock) {
            uint256 mintBlockNumbers = getMultiplier(lastProduceBlock,block.number);
            uint256 totalBMReward = mintBlockNumbers.mul(bmPerBlock);
            bountyMoney.mint(devaddr, totalBMReward.div(10));
            bountyMoney.mint(address(this), totalBMReward);
            lastProduceBlock = block.number;
        }

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 bmReward = multiplier.mul(bmPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        pool.accBMPerShare = pool.accBMPerShare.add(bmReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function depositWithPermit(uint256 _pid, uint256 _amount, uint8 v, bytes32 r, bytes32 s, uint deadline) public{
        PoolInfo storage pool = poolInfo[_pid];
        ITitanSwapV1Pair(address(pool.lpToken)).permit(msg.sender, address(this), _amount, deadline, v, r, s);
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = 0;
        if (user.amount > 0) {
            pending = user.amount.mul(pool.accBMPerShare).div(1e12).sub(user.rewardDebt);
            if(user.amount > pool.lpAmountRestricted) {
                uint256 difLpAmount = user.amount.sub(pool.lpAmountRestricted);
                uint256 burnAmount = pending.div(user.amount).mul(difLpAmount);
                // burn difamount
                bountyMoney.burn(address(this),burnAmount);
                pending = pending.sub(burnAmount);
            }
            safeBMTransfer(msg.sender, pending);

        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.reward = user.reward.add(pending);
        user.rewardDebt = user.amount.mul(pool.accBMPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterChef for WAGYU allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = 0;
        if (user.amount > 0) {
            pending = user.amount.mul(pool.accBMPerShare).div(1e12).sub(user.rewardDebt);
            if(user.amount > pool.lpAmountRestricted) {
                uint256 difLpAmount = user.amount.sub(pool.lpAmountRestricted);
                uint256 burnAmount = pending.div(user.amount).mul(difLpAmount);
                // burn difamount
                bountyMoney.burn(address(this),burnAmount);
                pending = pending.sub(burnAmount);
            }
            safeBMTransfer(msg.sender, pending);

        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.reward = user.reward.add(pending);
        user.rewardDebt = user.amount.mul(pool.accBMPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accBMPerShare).div(1e12).sub(user.rewardDebt);
        if(user.amount > pool.lpAmountRestricted) {
            uint256 difLpAmount = user.amount.sub(pool.lpAmountRestricted);
            uint256 burnAmount = pending.div(user.amount).mul(difLpAmount);
            // burn difamount
            bountyMoney.burn(address(this),burnAmount);
            pending = pending.sub(burnAmount);

        }
        safeBMTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.reward = user.reward.add(pending);
        user.rewardDebt = user.amount.mul(pool.accBMPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe wagyu transfer function, just in case if rounding error causes pool to not have enough SUSHIs.
    function safeBMTransfer(address _to, uint256 _amount) internal {
        uint256 bmBal = bountyMoney.balanceOf(address(this));
        if (_amount > bmBal) {
            bountyMoney.transfer(_to, bmBal);
        } else {
            bountyMoney.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}