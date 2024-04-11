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
deployer = _deployer(ajna_protocol)
scaled_pool = _scaled_pool(deployer)

print('PREPARE \n')
time.sleep(2)
ajna_protocol.get_runner().prepare_protocol_to_state_by_definition(protocol_definition.build())

print('TEST: LENDERS \n')
lenders = _lenders(ajna_protocol, scaled_pool)

print('TEST: BORROWERS \n')
borrowers = _borrowers(ajna_protocol, scaled_pool)

print('SUMMARIZE POOL \n')
pool_helper = PoolHelper(ajna_protocol, scaled_pool)
_summarize_pool(pool_helper)

#print('MKR DAI POOL \n')
#sdk = create_sdk_for_mkr_dai_pool()

print('COMPLETE \n')





