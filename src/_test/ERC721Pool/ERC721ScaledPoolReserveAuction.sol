// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }           from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory }    from "../../erc721/ERC721PoolFactory.sol";
import { IERC721Pool }          from "../../erc721/interfaces/IERC721Pool.sol";
import { IScaledPool }          from "../../base/interfaces/IScaledPool.sol";

import { BucketMath }           from "../../libraries/BucketMath.sol";
import { Maths }                from "../../libraries/Maths.sol";

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

contract ERC721ScaledReserveAuctionTest is ERC721HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _collectionPool = _deployCollectionPool();
        address[] memory poolAddresses_ = new address[](1);
        poolAddresses_[0] = address(_collectionPool);
        _mintAndApproveQuoteTokens(poolAddresses_, _lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(poolAddresses_, _borrower, 5_000 * 1e18);
        _mintAndApproveAjnaTokens( poolAddresses_, _bidder,   40_000 * 1e18);
        assertEq(_ajna.balanceOf(_bidder), 40_000 * 1e18);
        _mintAndApproveCollateralTokens(poolAddresses_, _borrower, 12);

        // lender adds liquidity and borrower draws debt
        changePrank(_lender);
        uint16 bucketId = 1663;
        uint256 bucketPrice = _collectionPool.indexToPrice(bucketId);
        assertEq(bucketPrice, 251_183.992399245533703810 * 1e18);
        _collectionPool.addQuoteToken(200_000 * 1e18, bucketId);

        // borrower draws debt
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _collectionPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _collectionPool.borrow(175_000 * 1e18, bucketId);

        _assertPool(
            PoolState({
                htp:                  175_168.269230769230850000 * 1e18,
                lup:                  bucketPrice,
                poolSize:             200_000 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 0.697370352137516918 * 1e18,
                borrowerDebt:         175_168.269230769230850000 * 1e18,
                actualUtilization:    0.875841346153846154 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        17_516.826923076923085000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower
            })
        );
        skip(26 weeks);
    }

    function testClaimableReserveNoAuction() external {
        // ensure empty state is returned
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: 0,
                auctionPrice:               0
            })
        );

        // ensure cannot take when no auction was started
        vm.expectRevert(IScaledPool.NoAuction.selector);
        _collectionPool.takeReserves(555 * 1e18);
        assertEq(_collectionPool.reserves(), 168.26923076923085 * 1e18);
    }

    function testClaimableReserveAuction() external {
        // borrower repays all debt (auction for full reserves)
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 205_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);

        // kick off a new auction
        uint256 expectedPrice = 1_000_000_000 * 1e18;
        uint256 expectedReserves = _collectionPool.reserves();
        assertEq(expectedReserves, 610.479702351371553626 * 1e18);
        uint256 expectedQuoteBalance = _quote.balanceOf(_bidder);
        changePrank(_bidder);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _collectionPool.startClaimableReserveAuction();
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        assertEq(_collectionPool.reserves(), 0);

        // bid once the price becomes attractive
        skip(24 hours);
        expectedPrice = 59.604644775 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(310.479702351371553626 * 1e18, expectedPrice);
        _collectionPool.takeReserves(300 * 1e18);
        expectedQuoteBalance += 300 * 1e18;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajna.balanceOf(_bidder), 22_118.6065675 * 1e18);
        expectedReserves -= 300 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );

        // bid max amount
        skip(5 minutes);
//        expectedPrice = 12_222 * 1e18;    // FIXME: price won't update until an hour passes
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(0, expectedPrice);
        _collectionPool.takeReserves(400 * 1e18);
        expectedQuoteBalance += expectedReserves;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajna.balanceOf(_bidder), 3_612.574198998766312082 * 1e18);
        expectedReserves = 0;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );

        // ensure take reverts after auction ends
        skip(72 hours);
        vm.expectRevert(IScaledPool.NoAuction.selector);
        _collectionPool.takeReserves(777 * 1e18);
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: 0,
                auctionPrice:               0
            })
        );
        assertEq(_collectionPool.reserves(), 0);
    }

    function testReserveAuctionPartiallyTaken() external {
        // borrower repays partial debt (auction leaves small buffer in reserves)
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 50_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);
        uint256 expectedReserves = _collectionPool.reserves();

        changePrank(_bidder);
        // _collectionPool.startClaimableReserveAuction();  // FIXME: underflow because CR formula returns negative value
        //assertEq(_collectionPool.reserves(), 5.555 * 1e18);

//        // partial take
//        skip(1 days);
//        uint256 expectedPrice = 59.604644775 * 1e18;
//        _collectionPool.takeReserves(200 * 1e18);
//        expectedReserves -= 200 * 1e18;
//        _assertReserveAuction(
//            ReserveAuctionState({
//                claimableReservesRemaining: expectedReserves,
//                auctionPrice:               expectedPrice
//            })
//        );
//
//        // wait until auction ends
//        skip(3 days);
//        expectedPrice = 0;
//        _assertReserveAuction(
//            ReserveAuctionState({
//                claimableReservesRemaining: expectedReserves,
//                auctionPrice:               expectedPrice
//            })
//        );
    }
}