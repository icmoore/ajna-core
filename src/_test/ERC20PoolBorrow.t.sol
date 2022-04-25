// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {Buckets} from "../libraries/Buckets.sol";

contract ERC20PoolBorrowTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithCollateral internal borrower2;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        borrower2 = new UserWithCollateral();
        collateral.mint(address(borrower2), 100 * 1e18);
        borrower2.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    // @notice: With 1 lender and 1 borrower tests
    // @notice: addQuoteToken (subsequently reallocation), addCollateral and borrow
    // @notice: borrower reverts:
    // @notice:     attempts to borrow more than available quote
    // @notice:     attempts to borrow more than their collateral supports
    // @notice:     attempts to borrow but stop price is exceeded
    function testBorrow() public {
        uint256 priceHighest = 4_000.927678580567537368 * 1e18;
        uint256 priceHigh = 3_514.334495390401848927 * 1e18;
        uint256 priceMed = 3_010.892022197881557845 * 1e18;
        uint256 priceLow = 2_503.519024294695168295 * 1e18;
        uint256 priceLowest = 2_000.221618840727700609 * 1e18;

        // lender deposits 10000 DAI in 5 buckets each
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceHighest);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceLow);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceLowest);

        // check pool balance
        assertEq(pool.totalQuoteToken(), 50_000 * 1e45);
        assertEq(pool.totalDebt(), 0);
        assertEq(pool.hpb(), priceHighest);

        // should revert if borrower wants to borrow a greater amount than in pool
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.InsufficientLiquidity.selector,
                pool.totalQuoteToken() - pool.totalDebt()
            )
        );
        borrower.borrow(pool, 60_000 * 1e18, 2_000 * 1e18);

        // should revert if insufficient collateral deposited by borrower
        vm.expectRevert(ERC20Pool.InsufficientCollateralForBorrow.selector);
        borrower.borrow(pool, 10_000 * 1e18, 4_000 * 1e18);

        // borrower deposit 100 MKR collateral
        borrower.addCollateral(pool, 10 * 1e18);

        // should revert if stop price exceeded
        vm.expectRevert(
            abi.encodeWithSelector(Buckets.BorrowPriceBelowStopPrice.selector, priceHigh)
        );
        borrower.borrow(pool, 15_000 * 1e18, 4_000 * 1e18);

        // borrower deposits additional 90 MKR collateral
        borrower.addCollateral(pool, 90 * 1e18);

        // get a 21_000 DAI loan from 3 buckets, loan price should be 3000 DAI
        assertEq(pool.estimatePriceForLoan(21_000 * 1e18), priceMed);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(borrower), priceMed, 21_000 * 1e45);
        borrower.borrow(pool, 21_000 * 1e18, 2_500 * 1e18);

        assertEq(quote.balanceOf(address(borrower)), 21_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 29_000 * 1e18);
        assertEq(pool.hpb(), priceHighest);
        assertEq(pool.lup(), priceMed);

        // check bucket deposit and debt at 3_010.892022197881557845
        (, , , uint256 deposit, uint256 debt, , , ) = pool.bucketAt(priceMed);
        assertEq(deposit, 9_000 * 1e45);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 29_000 * 1e45);
        assertEq(pool.totalDebt(), 21_000 * 1e45);
        // check borrower balance
        (uint256 borrowerDebt, uint256 depositedCollateral, ) = pool.borrowers(address(borrower));
        assertEq(borrowerDebt, 21_000 * 1e45);
        assertEq(depositedCollateral, 100 * 1e27);

        skip(8200);

        // borrow remaining 9_000 DAI from LUP
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 9_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(borrower), priceMed, 9_000 * 1e45);
        borrower.borrow(pool, 9_000 * 1e18, priceLow);

        assertEq(quote.balanceOf(address(borrower)), 30_000 * 1e18);
        assertEq(quote.balanceOf(address(pool)), 20_000 * 1e18);
        assertEq(pool.hpb(), priceHighest);
        assertEq(pool.lup(), priceMed);

        // check bucket debt at 2_503.519024294695168295
        (, , , deposit, debt, , , ) = pool.bucketAt(priceLow);
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e45);
        // check bucket debt at 3_010.892022197881557845
        (, , , deposit, debt, , , ) = pool.bucketAt(priceMed);
        assertEq(debt, 10000.013001099216594901568631000000000000000000000 * 1e45);
        assertEq(deposit, 0);
        // check bucket debt at 3_514.334495390401848927
        (, , , deposit, debt, , , ) = pool.bucketAt(priceHigh);
        assertEq(debt, 10_000 * 1e45);
        assertEq(deposit, 0);
        // check bucket debt at 4_000.927678580567537368
        (, , , deposit, debt, , , ) = pool.bucketAt(priceHighest);
        assertEq(debt, 10_000 * 1e45);
        assertEq(deposit, 0);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 20_000 * 1e45);
        assertEq(pool.totalDebt(), 30_000.2730230835484929329412510 * 1e45);

        // check borrower balances
        (borrowerDebt, depositedCollateral, ) = pool.borrowers(address(borrower));
        assertEq(borrowerDebt, 30_000.2730230835484929329412510 * 1e45);
        assertEq(depositedCollateral, 100 * 1e27);

        // deposit at 5_007.644384905151472283 price and reallocate entire debt
        lender.addQuoteToken(pool, address(lender), 40_000 * 1e18, 5_007.644384905151472283 * 1e18);
        assertEq(pool.hpb(), 5_007.644384905151472283 * 1e18);
        assertEq(pool.lup(), 5_007.644384905151472283 * 1e18);

        // check bucket debt at 2_503.519024294695168295
        (, , , deposit, debt, , , ) = pool.bucketAt(priceLow);
        assertEq(debt, 0);
        assertEq(deposit, 10_000 * 1e45);
        // check bucket debt at 3_010.892022197881557845
        (, , , deposit, debt, , , ) = pool.bucketAt(priceMed);
        assertEq(debt, 0);
        assertEq(deposit, 10000.013001099216594901568631000000000000000000000 * 1e45);
        // check bucket debt at 3_514.334495390401848927
        (, , , deposit, debt, , , ) = pool.bucketAt(priceHigh);
        assertEq(debt, 0);
        assertEq(deposit, 10000.130010992165949015686310 * 1e45);
        // check bucket debt at 4_000.927678580567537368
        (, , , deposit, debt, , , ) = pool.bucketAt(priceHighest);
        assertEq(debt, 0);
        assertEq(deposit, 10000.130010992165949015686310 * 1e45);
        // check bucket debt at 5_007.644384905151472283
        (, , , deposit, debt, , , ) = pool.bucketAt(5_007.644384905151472283 * 1e18);
        assertEq(debt, 30000.2730230835484929329412510 * 1e45);
        assertEq(deposit, 9999.7269769164515070670587490 * 1e45);
        // check pool balances
        assertEq(pool.totalQuoteToken(), 60_000 * 1e45);
        assertEq(pool.totalDebt(), 30000.2730230835484929329412510 * 1e45);
    }

    // @notice: With 1 lender and 2 borrowers tests addQuoteToken, addCollateral and borrow
    // @notice: on an undercollateralized pool
    // @notice: borrower2 reverts: attempts to borrow when pool is undercollateralized
    function testBorrowPoolUndercollateralization() public {
        uint256 priceHigh = 2_000.221618840727700609 * 1e18;
        uint256 priceMed = 1_004.989662429170775094 * 1e18;
        uint256 priceLow = 502.433988063349232760 * 1e18;

        // lender deposits 200_000 DAI in 3 buckets
        lender.addQuoteToken(pool, address(lender), 100_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 50_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 50_000 * 1e18, priceLow);

        // borrower1 takes a loan on 100_000 DAI
        assertEq(pool.estimatePriceForLoan(75_000 * 1e18), priceHigh);
        assertEq(pool.estimatePriceForLoan(125_000 * 1e18), priceMed);
        assertEq(pool.estimatePriceForLoan(175_000 * 1e18), priceLow);
        borrower.addCollateral(pool, 51 * 1e18);
        borrower.borrow(pool, 100_000 * 1e18, 1_000 * 1e18);

        assertEq(pool.estimatePriceForLoan(25_000 * 1e18), priceMed);
        assertEq(pool.estimatePriceForLoan(75_000 * 1e18), priceLow);
        assertEq(pool.estimatePriceForLoan(175_000 * 1e18), 0);
        borrower2.addCollateral(pool, 51 * 1e18);

        // should revert when taking a loan of 5_000 DAI that will drive pool undercollateralized
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Pool.PoolUndercollateralized.selector,
                0.976275672074051610091314286 * 1e27
            )
        );
        borrower2.borrow(pool, 5_000 * 1e18, 1_000 * 1e18);
    }

    // @notice: With 1 lender and 1 borrower tests addQuoteToken, addCollateral and borrow
    // @notice: verifying collateral
    function testBorrowTestCollateralValidation() public {
        uint256 priceLow = 13.578453165083418466 * 1e18;
        // lender deposits 10_000 DAI at 13.578453165083418466 * 1e18
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, priceLow);
        borrower.addCollateral(pool, 100 * 1e18);
        // should not revert when borrower takes a loan on 10_000 DAI
        borrower.borrow(pool, 1_000 * 1e18, 13.537 * 1e18);
    }

    // @notice: With 1 lender and 2 borrower tests HUP moves down
    // @notice: when pool is borrowed against and moves up when
    // @notice: quote token is added
    function testGetHup() public {
        uint256 priceHigh = 2_000.221618840727700609 * 1e18;
        uint256 priceMed = 1_004.989662429170775094 * 1e18;
        uint256 priceLow = 502.433988063349232760 * 1e18;

        // lender deposits 150_000 DAI in 3 buckets
        lender.addQuoteToken(pool, address(lender), 50_000 * 1e18, priceHigh);
        lender.addQuoteToken(pool, address(lender), 50_000 * 1e18, priceMed);
        lender.addQuoteToken(pool, address(lender), 50_000 * 1e18, priceLow);

        // borrow max possible from hdp
        borrower.addCollateral(pool, 51 * 1e18);
        borrower.borrow(pool, 50_000 * 1e18, 2_000 * 1e18);

        // check hup is below lup and lup equals hdp
        assertEq(priceHigh, pool.lup());
        assertEq(pool.hpb(), pool.lup());
        assertEq(pool.getHup(), priceMed);

        // borrow max possible from previous hup
        borrower2.addCollateral(pool, 51 * 1e18);
        borrower2.borrow(pool, 50_000 * 1e18, 1000 * 1e18);

        // check hup moves down
        assertEq(pool.getHup(), priceLow);
        assert(pool.getHup() < pool.lup());

        // add additional quote token to the maxed out priceMed bucket
        lender.addQuoteToken(pool, address(lender), 1000 * 1e18, priceMed);

        // check hup moves up as additional quote tokens become available
        assertEq(pool.getHup(), priceMed);
        assertEq(pool.getHup(), pool.lup());
    }
}
