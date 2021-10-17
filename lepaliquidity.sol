// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "./@openzeppelin/contracts/security/Pausable.sol";
import "./@openzeppelin/contracts/access/AccessControlEnumerable.sol";

interface TransferLepa {
    function transfer(address recipient,uint256 amount) external returns (bool);
}

contract LepaLiquidityBucket is Pausable,AccessControlEnumerable {
    TransferLepa private _lepaToken;

    struct Bucket {
        uint256 allocation;
        uint256 claimed;
    }

    mapping( address => Bucket) public users;

    uint256 public constant maxLimit =  10 * (10**6) * 10**18;
    uint256 public constant vestingSeconds = 365 * 86400;
    bytes32 public constant ALLOTTER_ROLE = keccak256("ALLOTTER_ROLE");
    uint256 public totalMembers;    
    uint256 public allocatedSum;
    uint256 public vestingStartEpoch;
    
    event GrantAllocationEvent(address allcationAdd, uint256 amount);    
    event ClaimAllocationEvent(address addr, uint256 balance);
    event VestingStartedEvent(uint256 epochtime);

    constructor(TransferLepa tokenAddress)  {
        require(address(tokenAddress) != address(0), "Token Address cannot be address 0");
        _lepaToken = tokenAddress;
        totalMembers = 0;
        allocatedSum = 0;
        vestingStartEpoch = 0;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ALLOTTER_ROLE, _msgSender());
    }

    function startVesting(uint256 epochtime) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role");
        require(vestingStartEpoch == 0, "Vesting already started.");
        vestingStartEpoch = epochtime;
        emit VestingStartedEvent(epochtime);
    }

    function GrantAllocation(address[] calldata _allocationAdd, uint256[] calldata _amount) external whenNotPaused {
      require(hasRole(ALLOTTER_ROLE, _msgSender()),"Must have allotter role");
      require(_allocationAdd.length == _amount.length);
      
      for (uint256 i = 0; i < _allocationAdd.length; ++i) {
            _GrantAllocation(_allocationAdd[i],_amount[i]);
        }
    }

    function _GrantAllocation(address allocationAdd, uint256 amount) internal {
        require(allocationAdd != address(0), "Invalid allocation address");
        require(amount >= 0, "Invalid allocation amount");
        require(amount >= users[allocationAdd].claimed, "Amount cannot be less than already claimed amount");
        require(allocatedSum - users[allocationAdd].allocation + amount <= maxLimit, "Limit exceeded");

        if(users[allocationAdd].allocation == 0) {                        
            totalMembers++;
        }
        allocatedSum = allocatedSum - users[allocationAdd].allocation + amount;
        users[allocationAdd].allocation = amount;        
        emit GrantAllocationEvent(allocationAdd, amount);        
    }

    function GetClaimableBalance(address userAddr) public view returns (uint256) {
        require(vestingStartEpoch > 0, "Vesting not initialized");

        Bucket memory userBucket = users[userAddr];        
        require(userBucket.allocation != 0, "Address is not registered");
        
        uint256 totalClaimableBal = userBucket.allocation/5; // 20% of allocation
        uint256 vestingPerSecond = (userBucket.allocation - totalClaimableBal)/vestingSeconds;

        totalClaimableBal = totalClaimableBal + (vestingPerSecond * (block.timestamp - vestingStartEpoch));

        if(totalClaimableBal > userBucket.allocation) {
            totalClaimableBal = userBucket.allocation;
        }

        require(totalClaimableBal > userBucket.claimed, "Vesting threshold reached");
        return totalClaimableBal - userBucket.claimed;
    }

    function ProcessClaim() external whenNotPaused {
        uint256 claimableBalance = GetClaimableBalance(_msgSender());
        require(claimableBalance > 0, "Claim amount invalid.");
        
        users[_msgSender()].claimed = users[_msgSender()].claimed + claimableBalance;
        emit ClaimAllocationEvent(_msgSender(), claimableBalance);
        require(_lepaToken.transfer(_msgSender(), claimableBalance), "Token transfer failed!"); 
    }

    /* Dont accept eth  */
    receive() external payable {
        revert("The contract does not accept direct payment.");
    }

    function pause() external{
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role");
        _pause();
    }

    function unpause() external{
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role");
        _unpause();
    }
}