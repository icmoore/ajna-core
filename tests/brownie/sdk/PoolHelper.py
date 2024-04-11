import math
import pytest
from tests.brownie.sdk import AjnaProtocol

# Layer of abstraction between pool contracts and brownie tests
class PoolHelper:
    def __init__(self, ajna_protocol: AjnaProtocol, pool):
        self.loans = ajna_protocol.loans
        self.pool = pool
        self.pool_info_utils = ajna_protocol.pool_info_utils

    def availableLiquidity(self):
        quoteBalance = self.quoteToken().balanceOf(self.pool.address)
        reserves = quoteBalance + self.debt() - self.pool.depositSize()
        return quoteBalance - reserves;

    def borrowerInfo(self, borrower_address):
        # returns (debt, collateral, t0NeutralPrice, thresholdPrice)
        return self.pool_info_utils.borrowerInfo(self.pool.address, borrower_address)

    def bucketInfo(self, index):
        # returns (index, price, quoteTokens, collateral, bucketLPs, scale, exchangeRate)
        return self.pool_info_utils.bucketInfo(self.pool.address, index)

    def collateralToken(self):
        return Contract(self.pool.collateralAddress())

    def debt(self):
        (debt, accruedDebt, debtInAuction, t0Debt2ToCollateral) = self.pool.debtInfo()
        return debt

    def hpb(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return hpb
    
    def hpbIndex(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return hpbIndex

    def htp(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return htp

    def indexToPrice(self, price_index: int):
        return self.pool_info_utils.indexToPrice(price_index)

    def lenderInfo(self, index, lender_address):
        # returns (lpBalance, lastQuoteDeposit)
        return self.pool.lenderInfo(index, lender_address)

    def loansInfo(self):
        # returns (poolSize, loansCount, maxBorrower, pendingInflator, pendingInterestFactor)
        # Not to be confused with pool.loansInfo which returns (maxBorrower, maxT0DebtToCollateral, noOfLoans)
        return self.pool_info_utils.poolLoansInfo(self.pool.address)

    def lup(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return lup

    def lupIndex(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return lupIndex

    def priceToIndex(self, price):
        return self.pool_info_utils.priceToIndex(price)

    def quoteToken(self):
        return Contract(self.pool.quoteTokenAddress())

    def utilizationInfo(self):
        return self.pool_info_utils.poolUtilizationInfo(self.pool.address)

    def get_origination_fee(self, amount):
        (interest_rate, _) = self.pool.interestRateInfo()
        fee_rate = max(interest_rate / 52, 0.0005 * 10**18)
        assert fee_rate >= (0.0005 * 10**18)
        assert fee_rate < (100 * 10**18)
        return fee_rate * amount / 10**18

    def price_to_index_safe(self, price):
        if price < MIN_PRICE:
            return self.pool_info_utils.priceToIndex(MIN_PRICE)
        elif price > MAX_PRICE:
            return self.pool_info_utils.priceToIndex(MAX_PRICE)
        else:
            return self.pool_info_utils.priceToIndex(price)
