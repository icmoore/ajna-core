#!/usr/bin/env python
# coding: utf-8

# ### Test Ajna SDK
# 
# Ganache UI Settings
# * Fork URL: https://eth-mainnet.alchemyapi.io/v2/EXgIPdwMutwBymbktM6aE54w_rIqBPs9
# * Port: 8545
# * Miner Gas Limit: 12000000
# * Hardfork: istanbul
# 
# ```
# > python -m pip install virtualenv --user
# > python3 -m virtualenv -p python3 ~/py3_kernel
# > source ~/py3_kernel/bin/activate
# > python -m pip install ipykernel
# > ipython kernel install --name py3 --user
# > deactivate
# > jupyter kernelspec list
# 
# > import os
# > cwd =  os.getcwd()
# > cwd += '/repos/ajna-core/tests/brownie/notebooks'
# > os.chdir(cwd)
# > !jupyter nbconvert --to script test.ipynb
# ```
# * https://stackoverflow.com/questions/30492623/using-both-python-2-x-and-python-3-x-in-ipython-notebook/37857536#37857536

# In[ ]:

import os
cwd =  os.getcwd().replace("tests/brownie","")
os.chdir(cwd)
print(cwd)

import math
import pytest
import time
from tests.brownie.sdk import *
from tests.brownie.conftest import PoolHelper

from brownie import test, network, Contract, ERC20PoolFactory, ERC20Pool, PoolInfoUtils
from brownie.exceptions import VirtualMachineError
from brownie.network.state import TxHistory
from brownie.utils import color

AJNA_ADDRESS = "0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079"
MIN_PRICE = 99836282890
MAX_PRICE = 1_004_968_987606512354182109771
ZRO_ADD = '0x0000000000000000000000000000000000000000'


def _deployer(ajna_protocol):
    return ajna_protocol.deployer

def _dai(ajna_protocol):
    return ajna_protocol.get_token(DAI_ADDRESS).get_contract()

def _mkr(ajna_protocol):
    return ajna_protocol.get_token(MKR_ADDRESS).get_contract()

def _weth(ajna_protocol):
    return ajna_protocol.get_token(WETH_ADDRESS).get_contract()

def _scaled_pool(deployer):
    scaled_factory = ERC20PoolFactory.deploy(AJNA_ADDRESS, {"from": deployer})
    scaled_factory.deployPool(MKR_ADDRESS, DAI_ADDRESS, 0.05 * 1e18, {"from": deployer})
    return ERC20Pool.at(
        scaled_factory.deployedPools("2263c4378b4920f0bef611a3ff22c506afa4745b3319c50b6d704a874990b8b2", MKR_ADDRESS, DAI_ADDRESS)
        )

def _lenders(ajna_protocol, scaled_pool):
    NUM_LENDERS = 10
    dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    amount = int(3_000_000_000 * 10**18 / NUM_LENDERS)
    lenders = []
    print("Initializing lenders")
    for _ in range(NUM_LENDERS):
        lender = ajna_protocol.add_lender()
        dai_client.top_up(lender, amount)
        dai_client.approve_max(scaled_pool, lender)
        lenders.append(lender)
    return lenders



def _borrowers(ajna_protocol, scaled_pool):
    NUM_BORROWERS = 10
    collateral_client = ajna_protocol.get_token(scaled_pool.collateralAddress())
    dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    amount = int(100_000 * 10**18 / NUM_BORROWERS)
    borrowers = []
    print("Initializing borrowers")
    for _ in range(NUM_BORROWERS):
        borrower = ajna_protocol.add_borrower()
        collateral_client.top_up(borrower, amount)
        collateral_client.approve_max(scaled_pool, borrower)
        dai_client.top_up(borrower, 100_000 * 10**18)  # for repayment of interest
        dai_client.approve_max(scaled_pool, borrower)
        assert collateral_client.get_contract().balanceOf(borrower) >= amount
        borrowers.append(borrower)
    return borrowers

def _summarize_pool(pool_helper):
    pool = pool_helper.pool
    poolDebt = pool_helper.debt()

    (_, poolCollateralization, poolActualUtilization, poolTargetUtilization) = pool_helper.utilizationInfo()
    (_, loansCount, _, _, _) = pool_helper.loansInfo()
    print(f"Actual utlzn:      {poolActualUtilization/1e18:>12.1%}\n"
          f"target utlzn:      {poolTargetUtilization/1e18:>12.1%}\n"
          f"collateralization: {poolCollateralization/1e18:>12.1%}\n"
          f"borrowerDebt:      {poolDebt/1e18:>12.1f}\n"
          f"loan count:        {loansCount:>12}")

    contract_quote_balance = pool_helper.quoteToken().balanceOf(pool)
    reserves = contract_quote_balance + poolDebt - pool.depositSize()
    pledged_collateral = pool.pledgedCollateral()
    (interest_rate, _) = pool.interestRateInfo()
    print(f"contract q bal:    {contract_quote_balance/1e18:>12.1f}\n"
          f"deposit:           {pool.depositSize()/1e18:>12.1f}\n"
          f"reserves:          {reserves/1e18:>12.1f}\n"
          f"pledged:           {pool.pledgedCollateral()/1e18:>12.1f}\n"
          f"rate:              {interest_rate/1e18:>12.4%}")

    lup = pool_helper.lup()
    htp = pool_helper.htp()
    poolCollateral = pool.pledgedCollateral()
    print(f"lup:               {lup/1e18:>12.3f}\n",
          f"htp:               {htp/1e18:>12.3f}")

protocol_definition = (
        InitialProtocolStateBuilder()
        .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
        .add_token(WETH_ADDRESS, WETH_RESERVE_ADDRESS)
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
    )

print('INITIALIZE \n')

ajna_protocol = AjnaProtocol(AJNA_ADDRESS)

print('PREPARE \n')
time.sleep(2)

ajna_protocol.get_runner().prepare_protocol_to_state_by_definition(
protocol_definition.build()      
    )

print('TEST: LENDERS \n')

deployer = _deployer(ajna_protocol)
scaled_pool = _scaled_pool(deployer)

amount = 200_000 * 10**18  # 200,000 DAI for each lender
dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())

lenders = []
for _ in range(10):
    lender = ajna_protocol.add_lender()
    dai_client.top_up(lender, amount)
    dai_client.approve_max(scaled_pool, lender)
    lenders.append(lender)

print('TEST: BORROWERS \n')

amount = 100 * 10**18  # 100 MKR for each borrower
dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
mkr_client = ajna_protocol.get_token(scaled_pool.collateralAddress())

borrowers = []
for _ in range(10):
    borrower = ajna_protocol.add_borrower()
    mkr_client.top_up(borrower, amount)
    mkr_client.approve_max(scaled_pool, borrower)
    dai_client.approve_max(scaled_pool, borrower)
    borrowers.append(borrower)

print('SUMMARIZE POOL \n')

pool_helper = PoolHelper(ajna_protocol, scaled_pool)
_summarize_pool(pool_helper)


print('SDK \n')

sdk = create_sdk_for_mkr_dai_pool()


print('COMPLETE \n')





