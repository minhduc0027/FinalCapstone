@IsTest
private class ReturnRefundCalculationServiceTests {
  private static void debugResult(String scenario, ReturnRefundResult result) {
    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-07 | ' +
        scenario +
        ' | unitPrice=' +
        result.unitPricePaid +
        ' | quantity=' +
        result.requestedQuantity +
        ' | reason=' +
        result.reasonCode +
        ' | condition=' +
        result.conditionCode +
        ' | rate=' +
        result.refundRate +
        ' | rawAmount=' +
        result.rawRefundAmount +
        ' | refundAmount=' +
        result.refundAmount +
        ' | valid=' +
        result.valid +
        ' | code=' +
        result.code
    );
  }

  @IsTest
  static void calculate_ShouldRefund100Percent_ForDefectUsed() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      1299000,
      2,
      'DEFECT',
      'USED'
    );

    Test.stopTest();

    debugResult('DEFECT_USED_100_PERCENT', result);

    System.assertEquals(true, result.valid);
    System.assertEquals('REFUND_CALCULATED', result.code);
    System.assertEquals(100, result.refundRate);
    System.assertEquals(2598000, result.rawRefundAmount);
    System.assertEquals(
      2598000,
      result.refundAmount,
      '2.598.000 đã chia hết cho đơn vị làm tròn 1.000'
    );
  }

  @IsTest
  static void calculate_ShouldRefund80Percent_AndRoundDown() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      1299000,
      2,
      'NOT_SATISFIED',
      'OPENED'
    );

    Test.stopTest();

    debugResult('NOT_SATISFIED_OPENED_80_PERCENT', result);

    System.assertEquals(true, result.valid);
    System.assertEquals('REFUND_CALCULATED', result.code);
    System.assertEquals(80, result.refundRate);

    System.assertEquals(
      2078400,
      result.rawRefundAmount,
      'Raw amount = 1.299.000 x 2 x 80%'
    );

    System.assertEquals(
      2078000,
      result.refundAmount,
      'Phải làm tròn xuống từ 2.078.400 thành 2.078.000'
    );
  }

  @IsTest
  static void calculate_ShouldRejectWrongItemUsed_WithZeroRate() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      1000000,
      1,
      'WRONG_ITEM',
      'USED'
    );

    Test.stopTest();

    debugResult('WRONG_ITEM_USED_ZERO_PERCENT', result);

    System.assertEquals(false, result.valid);
    System.assertEquals('REFUND_RATE_ZERO', result.code);
    System.assertEquals(0, result.refundRate);
    System.assertEquals(0, result.rawRefundAmount);
    System.assertEquals(0, result.refundAmount);
  }

  @IsTest
  static void calculate_ShouldRejectCustomerDamaged() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      2500000,
      1,
      'CUSTOMER_DAMAGED',
      'SEALED'
    );

    Test.stopTest();

    debugResult('CUSTOMER_DAMAGED_ZERO_PERCENT', result);

    System.assertEquals(false, result.valid);
    System.assertEquals('REFUND_RATE_ZERO', result.code);
    System.assertEquals(0, result.refundRate);
    System.assertEquals(0, result.refundAmount);
  }

  @IsTest
  static void calculate_ShouldNormalizeInputCodes() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      500000,
      2,
      '  not_satisfied  ',
      ' opened '
    );

    Test.stopTest();

    debugResult('NORMALIZED_CODES', result);

    System.assertEquals('NOT_SATISFIED', result.reasonCode);
    System.assertEquals('OPENED', result.conditionCode);
    System.assertEquals(80, result.refundRate);
    System.assertEquals(800000, result.refundAmount);
    System.assertEquals(true, result.valid);
  }

  @IsTest
  static void calculate_ShouldRejectZeroUnitPrice() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      0,
      2,
      'DEFECT',
      'SEALED'
    );

    Test.stopTest();

    debugResult('ZERO_UNIT_PRICE', result);

    System.assertEquals(false, result.valid);
    System.assertEquals('INVALID_REFUND_INPUT', result.code);
    System.assertEquals(0, result.refundAmount);
  }

  @IsTest
  static void calculate_ShouldRejectZeroQuantity() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      1000000,
      0,
      'DEFECT',
      'SEALED'
    );

    Test.stopTest();

    debugResult('ZERO_QUANTITY', result);

    System.assertEquals(false, result.valid);
    System.assertEquals('INVALID_REFUND_INPUT', result.code);
    System.assertEquals(0, result.refundAmount);
  }

  @IsTest
  static void calculate_ShouldRejectInvalidPolicyCode() {
    Test.startTest();

    ReturnRefundResult result = ReturnRefundCalculationService.calculate(
      1000000,
      1,
      'UNKNOWN_REASON',
      'SEALED'
    );

    Test.stopTest();

    debugResult('INVALID_POLICY_CODE', result);

    System.assertEquals(false, result.valid);
    System.assertEquals('INVALID_REFUND_POLICY_CODE', result.code);
    System.assertEquals(0, result.refundAmount);
  }
}
