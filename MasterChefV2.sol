
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./YuGiToken.sol";
import "./DragonToken.sol";

// MasterChef V2: Security Enhanced 

// 100% Remove the trust of the owner.
//
// 1.Removed migrator() function that could potentially lead to fund loss
//
// 2.All configuration functions are 48-hour timelocked:
//    0: airdropByOwner()
//    1: add()
//    2: addList()
//    3: setToken()
//    4: set()
//    5: setList()
//    6: updateMultiplier()
//    7: updateEmissionRate()
//    8: upgrade()
//
// To Check Timelock Status for each function. Call TIMELOCK() with fucntion id, if the function is locked, the returned value is "0". If the owner called unlock() to unlock one specific function, the returned value would be the timestamp 48 hours after the unlock() tx. The owner can call the unlocked fucntion after the timestamp. After owner calls the unlocked function, it would be locked again automatically. We have following restrictions to limit the owner's ability for unlocked functions:

// 3.Owner can NOT change _allocation point into an infinite number
// require (_allocPoint <= 200 && _depositFeeBP <= 1000, 'add: invalid allocpoints or deposit fee basis points');

// 4.Owner can NOT set deposit fee higher than 10%
// uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
// require (_allocPoint <= 5000 && _depositFeeBP <= 1000, 'set: invalid allocpoints or deposit fee basis points');

// 5.Owner can NOT set multiplier higher than 10
// require(multiplierNumber <= 10, 'multipler too high');

// 6.Owner can NOT set emission rate higher than the initial yugi per block
// require(_yugiPerBlock <= 1000000000000000000, 'must be smaller than the initial emission rate');

// 7.ReentrancyGuard for deposit(), withdraw(), emergencyWithdraw()

contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of YUGIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accYuGiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accYuGiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. YUGIs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that YUGIs distribution occurs.
        uint256 accYuGiPerShare;   // Accumulated YUGIs per share, times 1e12. See below.
        uint256 depositFeeBP;      // Deposit fee in basis points
    }

    // The YUGI TOKEN!
    YuGiToken public yugi;
    // The DRAGON TOKEN!
    DragonToken public dragon;
    // Dev address.
    address public devaddr;
    // YUGI tokens created per block.
    uint256 public yugiPerBlock = 1000000000000000000;
    // Bonus muliplier for early yugi makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // User list
    address[] public userList;
    // Only deposit user can get airdrop.
    mapping(address => bool) public userIsIn;
    uint256 public userInLength;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when YUGI mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    //// Timelock Configuration
    enum Functions { AIRDROPBYOWNER, ADD, ADDLIST, SETTOKEN, SET, SETLIST, UPDATEMULTIPLIER, UPDATEEMISSIONRATE, UPGRADE }    
    // 48 hours timelock
    uint256 private constant _TIMELOCK = 2 days;
    mapping(Functions => uint256) public TIMELOCK;
    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    modifier notLocked(Functions _fn) {
        require(TIMELOCK[_fn] != 0 && TIMELOCK[_fn] <= block.timestamp, "Function is timelocked");
        _;
    }

    constructor(
        YuGiToken _yugi,
        DragonToken _dragon,
        address _devaddr,
        address _feeAddress,
        uint256 _startBlock,
        address[] memory _poolTokens,
        uint256[] memory _poolAlloc
    ) public {
        yugi = _yugi;
        dragon = _dragon;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _yugi,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accYuGiPerShare: 0,
            depositFeeBP : 0
        }));
        totalAllocPoint = 1000;

        uint256 i;
        for (i = 0; i < _poolTokens.length; ++i) {
            poolInfo.push(PoolInfo({
                lpToken: IBEP20(_poolTokens[i]),
                allocPoint: 100,
                lastRewardBlock: startBlock,
                accYuGiPerShare: 0,
                depositFeeBP : 500
            }));
		}

        uint256 j;
        for (j = 0; j < _poolAlloc.length; ++j) {
            poolInfo[j+1].allocPoint = _poolAlloc[j];
		}

        updateStakingPool();
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function updateStakingPool() public {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = points.mul(4);
            poolInfo[0].allocPoint = points;
        }
    }

    // Internal function which is called when users deposit and withdraw
    function _userIn(address _user) internal {
        // a dummy amount to check if _user has deposited any tokens into the farm
        uint256 dummy = 0;
        for (uint256 pid = 0; pid < poolLength(); ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_user];
            if (user.amount == 0 || pool.allocPoint == 0) {
                continue;
            }
            dummy = dummy.add(user.amount);
        }
        if(dummy != 0) {
            userIsIn[_user] = true;
        } else {
            userIsIn[_user] = false;
        }
        userInLength = 0;
        for (uint256 i = 0; i < userList.length; i++) {
            if (userIsIn[userList[i]] = true) {
                userInLength = userInLength.add(1);
            }
        }
    }

    // Anyone can call airdrop to send any tokens as airdrop to available users in the userList array
    function airdrop(IBEP20 _token, uint256 _totalAmount) public {
        require(IBEP20(_token).balanceOf(msg.sender) >= _totalAmount);
        uint256 amountPerUser = _totalAmount.div(userInLength);
        for (uint256 i = 0; i < userList.length; i++) {
            if (userIsIn[userList[i]] == true) {
                IBEP20(_token).safeTransfer(userList[i], amountPerUser);
            }
        }
    }

    // TimeLocked
    // This function is timelocked and airdropByOwner() can only be called every 48 hours
    // Owner can send any tokens or mint YUGI tokens as airdrop to available users in the userList array
    // However there's limitations to the frequency and maximum amount of YUGI tokens can be airdropped
    // Owner can NOT airdrop more than 2% of the current YUGI totalSupply every 48 hours
    function airdropByOwner(IBEP20 _token, uint256 _value, bool _isMint) public onlyOwner notLocked(Functions.AIRDROPBYOWNER) {
        // if isMint == true, neglect _token parameter and mint YUGI as airdrop
        if (_isMint == true) {
            for (uint256 i = 0; i < userList.length; i++) {
                if (userIsIn[userList[i]] == false) {
                    continue;
                }
                // Owner can not airdrop more than 2% of the current totalSupply every 48 hours
                require(_value.div(yugi.totalSupply()).mul(50) <= 1);
                yugi.mint(userList[i], _value.div(userInLength));
            }
        } else if (_isMint == false) {
            airdrop(_token, _value);
        }
        // Refresh TimeLock for airdropByOwner() and add 48 hours lock
        unlock(Functions.AIRDROPBYOWNER);
    }

    // Read Only
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Can only be called by the owner
    // Should be monitored by everyone if there's any configuration
    // Unlock Timelock For Specified Function, it adds 3 days delay before it is possible to call the unlocked function.
    function unlock(Functions _fn) public onlyOwner {
        TIMELOCK[_fn] = block.timestamp + _TIMELOCK;
    }

    // Can only be called by the owner
    //Lock specific function immediately, makes it impossible to be called
    function timelock(Functions _fn) public onlyOwner {
        TIMELOCK[_fn] = 0;
    }

    // TimeLocked
    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint256 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) notLocked(Functions.ADD) {
        // RESTRICT ALLOCPOINT/DEPOSITFEE //
        require (_allocPoint <= 200 && _depositFeeBP <= 1000, 'add: invalid allocpoints or deposit fee basis points');

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accYuGiPerShare: 0,
            depositFeeBP : _depositFeeBP
        }));
        updateStakingPool();

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.ADD);
    }

    // TimeLocked
    // Add new tokens to the pool. Can only be called by the owner.
    function addList(address[] memory _lpToken, uint256 _allocPoint, uint256 _depositFeeBP) public onlyOwner notLocked(Functions.ADDLIST) {
        // RESTRICT ALLOCPOINT/DEPOSITFEE //
        require (_allocPoint <= 200 && _depositFeeBP <= 1000, 'add: invalid allocpoints or deposit fee basis points');
        // RESTRICT ADDLIST LENGTH //
        require (_lpToken.length <= 50, 'Forbid Adding Infinite LPTokens');

        uint256 i;
        for (i = 0; i < _lpToken.length; ++i) {
            poolInfo.push(PoolInfo({
                lpToken: IBEP20(_lpToken[i]),
                allocPoint: _allocPoint,
                lastRewardBlock: startBlock,
                accYuGiPerShare: 0,
                depositFeeBP : _depositFeeBP
            }));
            updateStakingPool();
		}

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.ADDLIST);
    }

    // TimeLocked
    // setToken, can only be called by the owner. Normally this function should NOT be unlocked.
    function setToken(uint _pid, IBEP20 _newToken) public onlyOwner notLocked(Functions.SETTOKEN) {

        PoolInfo storage pool = poolInfo[_pid];
        
        //CAN ONLY BE CALLED IF NO TOKEN IN THE POOL//
        require ( IBEP20(pool.lpToken).balanceOf(address(this)) != 0 && pool.lpToken != dragon);

        pool.lpToken = _newToken;

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.SETTOKEN);
    }

    // TimeLocked
    // Update the given pool's YUGI allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFeeBP, bool _withUpdate) public onlyOwner notLocked(Functions.SET) {
        // RESTRICT ALLOCPOINT
        require (_allocPoint <= 5000 && _depositFeeBP <= 1000, 'set: invalid allocpoints or deposit fee basis points');

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.SET);
    }

    // TimeLocked
    // Update the given pools' YUGI allocation point. Can only be called by the owner.
    function setList(uint256[] memory _poolAlloc, uint256[] memory _depositFeeBP) public onlyOwner notLocked(Functions.SETLIST) {
        uint256 i;
        for (i = 0; i < _poolAlloc.length; ++i) {
        // RESTRICT ALLOCPOINT
            require (_poolAlloc[i] <= 200 && _depositFeeBP[i] <= 1000, 'setList: invalid allocpoints or deposit fee basis points');
            poolInfo[i+1].allocPoint = _poolAlloc[i];
            totalAllocPoint = totalAllocPoint.sub(poolInfo[i+1].allocPoint).add(_poolAlloc[i]);
            uint256 prevAllocPoint = poolInfo[i+1].allocPoint;
            poolInfo[i+1].allocPoint = _poolAlloc[i];
            if (prevAllocPoint != _poolAlloc[i]) {
                updateStakingPool();
            }
            poolInfo[i+1].depositFeeBP = _depositFeeBP[i];
		}

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.SETLIST);
    }

    // TimeLocked
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner notLocked(Functions.UPDATEMULTIPLIER) {
        require(multiplierNumber <= 10, 'multipler too high');
        BONUS_MULTIPLIER = multiplierNumber;

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.UPDATEMULTIPLIER);
    }

    // TimeLocked
    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _yugiPerBlock) public onlyOwner notLocked(Functions.UPDATEEMISSIONRATE) {
        require(_yugiPerBlock <= 1000000000000000000, 'must be smaller than the initial emission rate');
        massUpdatePools();
        yugiPerBlock = _yugiPerBlock;
        emit UpdateEmissionRate(msg.sender, _yugiPerBlock);

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.UPDATEEMISSIONRATE);
    }

    // TimeLocked
    function upgrade(address _address) public onlyOwner notLocked(Functions.UPGRADE) {
        yugi.transferOwnership(_address);
        dragon.transferOwnership(_address);

        //TIMELOCK THIS FUNCTION AFTER IT IS CALLED
        timelock(Functions.UPGRADE);
    }

    // Read Only
    // View function to see pending YUGIs on frontend.
    function pendingYuGi(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accYuGiPerShare = pool.accYuGiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 yugiReward = multiplier.mul(yugiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accYuGiPerShare = accYuGiPerShare.add(yugiReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accYuGiPerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingYuGiAll(address _user) public view returns (uint256) {
        uint256 pending = 0;
        for (uint256 pid = 0; pid < poolLength(); ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_user];
            if (user.amount == 0 || pool.allocPoint == 0) {
                continue;
            }
            pending = pending.add(pendingYuGi(pid, _user));
        }
        return pending;
    }

    // Can Be Called By Anyone
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Can Be Called By Anyone
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 yugiReward = multiplier.mul(yugiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        yugi.mint(devaddr, yugiReward.div(10));
        yugi.mint(address(this), yugiReward);
        pool.accYuGiPerShare = pool.accYuGiPerShare.add(yugiReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Non-Reentrant, Can Be Called By Anyone
    // Deposit LP tokens to MasterChef for YUGI allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accYuGiPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeYuGiTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
            _userIn(msg.sender);
            userList.push(msg.sender);
        }
        user.rewardDebt = user.amount.mul(pool.accYuGiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Non-Reentrant, Can Be Called By Anyone
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accYuGiPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeYuGiTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            //update userIsIn array
            _userIn(msg.sender);
        }
        user.rewardDebt = user.amount.mul(pool.accYuGiPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Non-Reentrant, Can Be Called By Anyone
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        _userIn(msg.sender);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe Function
    // Safe yugi transfer function, just in case if rounding error causes pool to not have enough YUGIs.
    function safeYuGiTransfer(address _to, uint256 _amount) internal {
        uint256 yugiBal = yugi.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > yugiBal) {
            transferSuccess = yugi.transfer(_to, yugiBal);
        } else {
            transferSuccess = yugi.transfer(_to, _amount);
        }
        require(transferSuccess, "safeYuGiTransfer: transfer failed");
    }

    // Safe Function
    // Update dev address by the owner.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    // Safe Function
    // Update fee address by the owner.
    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }
}
