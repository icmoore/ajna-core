// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Ajna Pool Factory
 * @dev   Used to deploy both funigible and non fungible pools
 */
interface IPoolFactory {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     *  @notice Emitted when a new pool is created
     *  @param pool the address of the new pool
     */
    event PoolCreated(address pool);

    /**
     *  @notice ETH cannot be used for collateral or quote token, use WETH
     */
    error WethOnly();

    /**
     *  @notice A pool with same collateral and quote token already exists
     */
    error PoolAlreadyExists();

    /**
     *  @notice Deploys a cloned pool for the given collateral and quote token
     *  @dev    Pool must not already exist, and must use WETH instead of ETH
     *  @param  collateral_ Address of ERC20 collateral token
     *  @param  collateral_ Address of ERC20 quote token
     */
    function deployPool(address collateral_, address quote_) external returns (address pool_);
}
