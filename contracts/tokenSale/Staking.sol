// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract Staking is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;

    bool public isLocked;
    bool public isAnEmergency;

    IERC20 public stakingToken;
    uint256 public totalStaked;

    // the following address will be used instead of the native token of the network
    address constant public asNativeToken = 0x1111111111111111111010101010101010101010;

    mapping (address => uint256) public stakingDeposits;
    mapping (address => uint256) public stakingStartTimes;

    uint256 public minimumAmountToStake;

    // 100,000,000 means 100% 
    uint256 public stakingDailyYeild;

    event Stake(address indexed staker, uint256 stakedAmount);
    event UnStake(address indexed staker, uint256 stakedAmount);
    event WithdrawReward(address indexed staker, uint256 withdrawingAmount);

    function __Staking_init(
        address _stakingToken,  
        uint256 _minimumAmountToStake,
        uint256 _stakingDailyYeild
    ) internal onlyInitializing {
        
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        require(
            _stakingToken != address(0),
            "TokenSale: saling token is zero"
        );

        require(
            _minimumAmountToStake > 0,
            "TokenSale: minimum amount to stake is 0"
        );

        require(
            _stakingDailyYeild > 0,
            "TokenSale: staking yield is 0"
        );

        stakingToken = IERC20(_stakingToken);

        minimumAmountToStake = _minimumAmountToStake;
        stakingDailyYeild = _stakingDailyYeild;

        isLocked = true;
    }

    /**
     * @dev charge the vesting contract
     */
    function chargeStaking(address tokenSaleCharger, uint256 chargingAmnt) external onlyOwner {

        require(stakingToken.allowance(tokenSaleCharger, address(this)) >= chargingAmnt,
            "TokenSale: there is not enough token for charge"
        );

        // TODO: add event

        stakingToken.transferFrom(tokenSaleCharger, address(this), chargingAmnt);

        isLocked = false;
    }


    function stake(uint256 _amount) external {
        require(
            !isLocked,
            "StakingPool: is locked"
        );

        require(
            !isAnEmergency,
            "StakingPool: is in emergency"
        );
        
        require(
            _amount >= minimumAmountToStake, 
            "StakingPool: staking amount is than minimum"
        );

        require(
            stakingStartTimes[_msgSender()] == 0, 
            "StakingPool: user has already staked"
        );

        require(
            stakingDeposits[_msgSender()] == 0, 
            "StakingPool: user has already staked"
        );
  
        stakingToken.transferFrom(
            _msgSender(),
            address(this),
            _amount
        );

        stakingStartTimes[_msgSender()] = block.timestamp;

        stakingDeposits[_msgSender()] = _amount;

        totalStaked = totalStaked.add(_amount);

        emit Stake(_msgSender(), _amount);
    }


    function claim() external {
        require(
            !isAnEmergency,
            "StakingPool: is in emergency"
        );
        
        require(
            stakingDeposits[_msgSender()] >= 0, 
            "StakingPool: user haven't staked"
        );

        require(
            stakingStartTimes[_msgSender()] >= 0, 
            "StakingPool: user haven't staked"
        );
        

        uint256 reward = calculateReward(
            stakingDeposits[_msgSender()], 
            block.timestamp.sub(stakingStartTimes[_msgSender()])
        );

        if (reward == 0) {
            uint256 userDeposit = stakingDeposits[_msgSender()];

            stakingStartTimes[_msgSender()] = 0;

            stakingDeposits[_msgSender()] = 0;

            require(
                stakingToken.transfer(_msgSender(), userDeposit)
            );

            emit UnStake(_msgSender(), userDeposit);

        } else {
            uint256 userDeposit = stakingDeposits[_msgSender()] + reward;

            stakingStartTimes[_msgSender()] = 0;

            stakingDeposits[_msgSender()] = 0;

            require(
                stakingToken.transfer(_msgSender(), userDeposit)
            );

            emit UnStake(_msgSender(), userDeposit);
            emit WithdrawReward(_msgSender(), reward);
        }
    }


    function calculateReward(uint256 _stakedAmount, uint256 _stakedTime) public view returns (uint256) {
        uint256 dayInSecond = 1 days;

        uint256 rate = _stakedTime;
        rate = rate.mul(stakingDailyYeild);
        rate = rate.div(dayInSecond);

        uint256 reward = _stakedAmount;
        reward = reward.mul(rate);

        // divide by 100,000,000 to bypass the stakingAPY effect
        reward = reward.div(10 ** 8);

        return reward;
    }


    function declareEmergency()
        external
        onlyOwner
    {
        isLocked = true;
        isAnEmergency = true;
    }

    function emergentWithdraw() external {
        require(
            isAnEmergency,
            "StakingPool: it's not an emergency"
        );

        require(
            stakingDeposits[_msgSender()] >= 0, 
            "StakingPool: user haven't staked"
        );

        uint256 userDeposit = stakingDeposits[_msgSender()];

        stakingStartTimes[_msgSender()] = 0;

        stakingDeposits[_msgSender()] = 0;

        require(
            stakingToken.transfer(_msgSender(), userDeposit)
        );

        emit UnStake(_msgSender(), userDeposit);
    }


        /**
     * @dev the owner of the vesting can un-lock the vesting 
     */
    function evacuateTokenSale(address stuckToken, address payable reciever, uint256 amount) external onlyOwner {
        require(
            isAnEmergency,
            "StakingPool: evacuation only possible when vesting is in emergency"
        );

        require(
            isLocked,
            "StakingPool: evacuation only possible when vesting is locked"
        );

        if (stuckToken == asNativeToken) {

            reciever.transfer(amount);

            // require(
            //     reciever.transfer(amount),
            //     "VestingWallet: couldn't transfer native token"
            // );
        } else {

            IERC20 theToken = IERC20(stuckToken);
            require(
                theToken.transfer(reciever, amount),
                "StakingPool: couldn't transfer token"
            );
        }        
    }
}