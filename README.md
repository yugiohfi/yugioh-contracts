# MasterChef V2: Security Enhanced 

### 100% Remove the trust of the owner.

### 1.Removed migrator() function that could potentially lead to fund loss

### 2.All configuration functions are 48-hour timelocked:
    0: airdropByOwner()
    1: add()
    2: addList()
    3: setToken()
    4: set()
    5: setList()
    6: updateMultiplier()
    7: updateEmissionRate()
    8: upgrade()

 To Check Timelock Status for each function. Call TIMELOCK() with fucntion id, if the function is locked, the returned value is "0". If the owner called unlock() to unlock one specific function, the returned value would be the timestamp 48 hours after the unlock() tx. The owner can call the unlocked fucntion after the timestamp. After owner calls the unlocked function, it would be locked again automatically. We have following restrictions to limit the owner's ability for unlocked functions:

### 3.Owner can NOT change _allocation point into an infinite number
 require (_allocPoint <= 200 && _depositFeeBP <= 1000, 'add: invalid allocpoints or deposit fee basis points');

### 4.Owner can NOT set deposit fee higher than 10%
 uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
 require (_allocPoint <= 5000 && _depositFeeBP <= 1000, 'set: invalid allocpoints or deposit fee basis points');

### 5.Owner can NOT set multiplier higher than 10
 
 require(multiplierNumber <= 10, 'multipler too high');

### 6.Owner can NOT set emission rate higher than the initial yugi per block
 require(_yugiPerBlock <= 1000000000000000000, 'must be smaller than the initial emission rate');

### 7.ReentrancyGuard for deposit(), withdraw(), emergencyWithdraw()


## YUGI TOKEN
0x0B9e6429EBf7E59d3FeBf5b3eA1Df1d970242E0F
## YUGI-BUSD
0xA727Bba71e8cfEdbA3c8c53D5E50c297beB88d29
## YUGI-WBNB
0xAA5AeB33D7a346fB9E561C5E182D52F9Ac0aa33B

## DRAGON TOKEN
0x0d42dF10a117aA2025c6D4954838eC800a180420
## YUGI FARM
0xc9d6FA14aCc9ad8c7Af96e7d61f594FD03e3c699
