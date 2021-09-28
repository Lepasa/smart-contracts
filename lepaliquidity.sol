// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "./@openzeppelin/contracts/security/Pausable.sol";
import "./@openzeppelin/contracts/access/Ownable.sol";
import "./@openzeppelin/contracts/utils/math/SafeMath.sol";

interface TransferLepa {
    function transfer(address recipient,uint256 amount) external;
}

contract LepaLiquidityBucket is Pausable,Ownable {
    using SafeMath for uint256;
    TransferLepa private _lepaToken;

    struct Bucket {
        uint256 allocation;
        uint256 claimed;
    }

    mapping( address => Bucket) public users;

    uint256 public maxLimit =  10 * (10**6) * 10**18;
    uint256 public vestingDays = 365;
    uint256 public totalMembers;    
    uint256 public allocatedSum;
    uint256 public contractCreation;

    event GrantAllocationEvent(address allcationAdd, uint256 amount);    
    event ClaimBalanceEvent(address addr, uint256 balance);

    constructor(TransferLepa tokenAddress)  {
        _lepaToken = tokenAddress;
        totalMembers = 0;
        allocatedSum = 0;
        contractCreation = 0;
    }

    function setCreationTime(uint256 epochtime) public onlyOwner {
        require(contractCreation == 0, "Vesting already started.");
        contractCreation = epochtime;
    }

    function GrantAllocation(address[] calldata _allocationAdd, uint256[] calldata _amount) public onlyOwner whenNotPaused {
      require(_allocationAdd.length == _amount.length);
      
      for (uint256 i = 0; i < _allocationAdd.length; ++i) {
            _GrantAllocation(_allocationAdd[i],_amount[i]);
        }
    }

    function _GrantAllocation(address allocationAdd, uint256 amount) internal {
        require(allocationAdd != address(0), "Invalid allocation address");
        require(amount > 0, "Invalid allocation amount");
        require(amount > users[allocationAdd].claimed, "Amount cannot be less than already claimed amount");
        require(allocatedSum.sub(users[allocationAdd].allocation).add(amount) <= maxLimit, "Limit exceed");

        if(users[allocationAdd].allocation == 0) {                        
            totalMembers = totalMembers.add(1);
        }
        allocatedSum = allocatedSum.sub(users[allocationAdd].allocation).add(amount);
        users[allocationAdd].allocation = amount;        
        emit GrantAllocationEvent(allocationAdd, amount);        
    }

    function GetClaimableBalance(address userAddr) public view returns (uint256) {
        require(contractCreation > 0, "Vesting not initialzed");
        uint256 claimableBal = 0;
        Bucket memory userBucket = users[userAddr];        
        require(userBucket.allocation != 0, "Address is not registered");
        
        claimableBal = userBucket.allocation.div(5); // 20% of allocation
        
        uint256 vestingAmount = CalculateVestingAmount(userBucket.allocation.sub(claimableBal), vestingDays);
        claimableBal = claimableBal.add(vestingAmount.mul(block.timestamp - contractCreation));

        if(claimableBal > userBucket.allocation) {
            claimableBal = userBucket.allocation;
        }

        require(claimableBal > userBucket.claimed, "Insufficient claim amount");
        return claimableBal.sub(userBucket.claimed);
    }

    function ProcessClaim() public whenNotPaused {
        uint256 claimableBalance = GetClaimableBalance(_msgSender());
        require(claimableBalance > 0, "Claim amount invalid.");
        
        users[_msgSender()].claimed = users[_msgSender()].claimed.add(claimableBalance);
        _lepaToken.transfer(_msgSender(), claimableBalance);

        emit ClaimBalanceEvent(_msgSender(), claimableBalance);
    }

    function CalculateVestingAmount(uint256 amount, uint256 vdays) private pure returns (uint256) {        
        return amount.div(GetDaysTimstamp(vdays));
    }

    function GetDaysTimstamp(uint256 vdays) private pure returns (uint256) {        
        return vdays.mul(86400); // 1 day = 86400 seconds        
    }
    
    /* Dont accept eth  */
    receive() external payable {
        revert("The contract does not accept direct payment.");
    }

    function pause() public onlyOwner{
        _pause();
    }

    function unpause() public onlyOwner{
        _unpause();
    }
}