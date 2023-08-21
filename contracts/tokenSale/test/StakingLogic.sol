// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Staking.sol";

contract StakingLogic is Staking {
    function initialize(
        address _stakingToken,  
        uint256 _minimumAmountToStake,
        uint256 _stakingDailyYeild
    ) public initializer {
        Staking.__Staking_init(
            _stakingToken,
            _minimumAmountToStake,
            _stakingDailyYeild
        );
    }
}