public inherited sharing class ReturnRefundCalculationService {
  private static final Set<String> VALID_REASON_CODES = new Set<String>{
    'DEFECT',
    'WRONG_ITEM',
    'NOT_SATISFIED',
    'CUSTOMER_DAMAGED'
  };

  private static final Set<String> VALID_CONDITION_CODES = new Set<String>{
    'SEALED',
    'OPENED',
    'USED'
  };

  public static ReturnRefundResult calculate(
    Decimal unitPricePaid,
    Decimal requestedQuantity,
    String reasonCode,
    String conditionCode
  ) {
    System.debug(
      LoggingLevel.INFO,
      'REQ-07 | Refund calculation started' +
        ' | unitPricePaid=' +
        unitPricePaid +
        ' | requestedQuantity=' +
        requestedQuantity +
        ' | reasonCode=' +
        reasonCode +
        ' | conditionCode=' +
        conditionCode
    );

    String normalizedReasonCode = normalizeCode(reasonCode);

    String normalizedConditionCode = normalizeCode(conditionCode);

    if (
      unitPricePaid == null ||
      unitPricePaid <= 0 ||
      requestedQuantity == null ||
      requestedQuantity <= 0
    ) {
      return buildResult(
        unitPricePaid,
        requestedQuantity,
        normalizedReasonCode,
        normalizedConditionCode,
        0,
        0,
        0,
        false,
        'INVALID_REFUND_INPUT',
        'Đơn giá và số lượng trả phải lớn hơn 0.'
      );
    }

    if (
      !VALID_REASON_CODES.contains(normalizedReasonCode) ||
      !VALID_CONDITION_CODES.contains(normalizedConditionCode)
    ) {
      return buildResult(
        unitPricePaid,
        requestedQuantity,
        normalizedReasonCode,
        normalizedConditionCode,
        0,
        0,
        0,
        false,
        'INVALID_REFUND_POLICY_CODE',
        'Lý do trả hàng hoặc tình trạng sản phẩm không hợp lệ.'
      );
    }

    Decimal refundRate = SmartReturnConfigService.getRefundRate(
      normalizedConditionCode,
      normalizedReasonCode
    );

    Decimal rawRefundAmount =
      unitPricePaid *
      requestedQuantity *
      refundRate /
      100;

    Decimal roundingUnit = SmartReturnConfigService.getRefundRounding();

    Decimal roundedRefundAmount = roundDown(rawRefundAmount, roundingUnit);

    Boolean valid = refundRate > 0;

    ReturnRefundResult result = buildResult(
      unitPricePaid,
      requestedQuantity,
      normalizedReasonCode,
      normalizedConditionCode,
      refundRate,
      rawRefundAmount,
      roundedRefundAmount,
      valid,
      valid ? 'REFUND_CALCULATED' : 'REFUND_RATE_ZERO',
      valid
        ? 'Số tiền hoàn đã được tính thành công.'
        : 'Sản phẩm không đủ điều kiện hoàn tiền.'
    );

    System.debug(
      LoggingLevel.INFO,
      'REQ-07 | Refund calculation completed' +
        ' | refundRate=' +
        result.refundRate +
        ' | rawAmount=' +
        result.rawRefundAmount +
        ' | roundingUnit=' +
        roundingUnit +
        ' | refundAmount=' +
        result.refundAmount +
        ' | valid=' +
        result.valid +
        ' | code=' +
        result.code
    );

    return result;
  }

  private static Decimal roundDown(Decimal amount, Decimal roundingUnit) {
    if (amount == null || roundingUnit == null || roundingUnit <= 0) {
      return amount == null ? 0 : amount;
    }

    Decimal multiplier = (amount / roundingUnit)
      .setScale(0, RoundingMode.FLOOR);

    return multiplier * roundingUnit;
  }

  private static String normalizeCode(String code) {
    return String.isBlank(code) ? null : code.trim().toUpperCase();
  }

  private static ReturnRefundResult buildResult(
    Decimal unitPricePaid,
    Decimal requestedQuantity,
    String reasonCode,
    String conditionCode,
    Decimal refundRate,
    Decimal rawRefundAmount,
    Decimal refundAmount,
    Boolean valid,
    String code,
    String message
  ) {
    ReturnRefundResult result = ReturnRefundResult.create(
      unitPricePaid,
      requestedQuantity,
      reasonCode,
      conditionCode,
      refundRate,
      rawRefundAmount,
      refundAmount,
      valid,
      code,
      message
    );

    System.debug(
      LoggingLevel.INFO,
      'REQ-07 | Refund result' +
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

    return result;
  }
}
