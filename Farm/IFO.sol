// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/token/ERC20/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/utils/ReentrancyGuard.sol";

import "./Governor.sol";

contract IFO is ReentrancyGuard, Governor {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // Info of each user.
  struct UserInfo {
      uint256 amount;   // How many tokens the user has provided.
      bool claimed;  // default false
  }

  uint256 public startBlock;
  uint256 public endBlock;

  IERC20 public stakeToken;
  IERC20 public offeringToken;

  // Total amount of raising tokens need to be raised
  uint256 public raisingAmount;
  // Total amount of offeringToken that will offer
  uint256 public offeringAmount;
  // Total raised amount of burnToken, can be higher than raisingAmount
  uint256 public totalAmount;

  mapping (address => UserInfo) public userInfo;
  address[] public addressList;


  event Deposit(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

  constructor(
      IERC20 _stakeToken,
      IERC20 _offeringToken,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _offeringAmount,
      uint256 _raisingAmount
  ) public {
      stakeToken = _stakeToken;
      offeringToken = _offeringToken;
      startBlock = _startBlock;
      endBlock = _endBlock;
      offeringAmount = _offeringAmount;
      raisingAmount = _raisingAmount;
      govAddress = msg.sender;
  }

  function setOfferingAmount(uint256 _offerAmount) external onlyGov {
    require (block.number < startBlock, 'Cannot change after start');
    offeringAmount = _offerAmount;
  }

  function setRaisingAmount(uint256 _raisingAmount) external onlyGov {
    require (block.number < startBlock, 'Cannot change after start');
    raisingAmount = _raisingAmount;
  }

  function deposit(uint256 _amount) external {
    require (block.number > startBlock && block.number < endBlock, 'Has not started');
    require (_amount > 0, 'need _amount > 0');
    uint256 preStakeBalance = getTotalStakeTokenBalance();
    stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
    if (userInfo[msg.sender].amount == 0) {
      addressList.push(address(msg.sender));
    }
    uint256 finalDepositAmount = getTotalStakeTokenBalance().sub(preStakeBalance);
    userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(finalDepositAmount);
    totalAmount = totalAmount.add(finalDepositAmount);
    emit Deposit(msg.sender, finalDepositAmount);
  }

  function harvest() external nonReentrant {
    require (block.number > endBlock, 'Has not ended yet');
    require (userInfo[msg.sender].amount > 0, 'Have you participated?');
    require (!userInfo[msg.sender].claimed, 'Nothing to harvest');
    uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
    uint256 refundingTokenAmount = getRefundingAmount(msg.sender);
    offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
    if (refundingTokenAmount > 0) {
      stakeToken.safeTransfer(address(msg.sender), refundingTokenAmount);
    }
    userInfo[msg.sender].claimed = true;
    emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
  }

  function hasHarvest(address _user) external view returns(bool) {
      return userInfo[_user].claimed;
  }

  // allocation 100000 means 0.1(10%), 1 meanss 0.000001(0.0001%), 1000000 means 1(100%)
  function getUserAllocation(address _user) public view returns(uint256) {
    return userInfo[_user].amount.mul(1e12).div(totalAmount).div(1e6);
  }

  // allocation 100000 means 0.1(10%), 1 meanss 0.000001(0.0001%), 1000000 means 1(100%)
  function getTotalStakeTokenBalance() public view returns(uint256) {
    return stakeToken.balanceOf(address(this));
  }

  // get the amount of IFO token you will get
  function getOfferingAmount(address _user) public view returns(uint256) {
    if (totalAmount > raisingAmount) {
      uint256 allocation = getUserAllocation(_user);
      return offeringAmount.mul(allocation).div(1e6);
    }
    else {
      // userInfo[_user] / (raisingAmount / offeringAmount)
      return userInfo[_user].amount.mul(offeringAmount).div(raisingAmount);
    }
  }

  // get the amount of lp token you will be refunded
  function getRefundingAmount(address _user) public view returns(uint256) {
    if (totalAmount <= raisingAmount) {
      return 0;
    }
    uint256 allocation = getUserAllocation(_user);
    uint256 payAmount = raisingAmount.mul(allocation).div(1e6);
    return userInfo[_user].amount.sub(payAmount);
  }

  function getAddressListLength() external view returns(uint256) {
    return addressList.length;
  }

  function beforeWithdraw() external onlyGov {
    require (block.number < startBlock, 'Dont rugpull');
    offeringToken.safeTransfer(address(msg.sender), offeringToken.balanceOf(address(this)));
  }

  function finalWithdraw(uint256 _stakeTokenAmount, uint256 _offerAmount) external onlyGov {
    require (block.number > endBlock, 'Dont rugpull');
    uint256 stakeBalance = getTotalStakeTokenBalance();
    require (_stakeTokenAmount <= stakeBalance, 'not enough stakeToken');
    require (_offerAmount <= offeringToken.balanceOf(address(this)), 'not enough reward token');
    stakeToken.safeTransfer(address(msg.sender), _stakeTokenAmount);
    offeringToken.safeTransfer(address(msg.sender), _offerAmount);
  }

  // If something breaks
  function updateEndBlock(uint256 _endBlock) external onlyGov {
    endBlock = _endBlock;
  }

  // If something breaks
  function updateStartBlock(uint256 _startBlock) external onlyGov {
    require (block.number < startBlock, 'Cannot change after start');
    startBlock = _startBlock;
  }
}