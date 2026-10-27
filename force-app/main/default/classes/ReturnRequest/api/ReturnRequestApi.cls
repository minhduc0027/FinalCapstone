@RestResource(urlMapping='/smartreturn/v1/return-requests/*')
global with sharing class ReturnRequestApi {
  @HttpPost
  global static void createReturn() {
    RestResponse response = RestContext.response;

    try {
      ReturnApiRequest payload = parseRequest(RestContext.request);
      validateRequest(payload);

      String externalRequestId = payload.externalRequestId.trim();

      Return_Request__c existingRequest = ReturnApiSelector.selectByExternalRequestId(
        externalRequestId
      );

      if (existingRequest != null) {
        writeJson(response, 200, buildCreateResponse(existingRequest));
        return;
      }

      Order orderRecord = ReturnApiSelector.selectOrder(
        payload.orderNumber.trim(),
        payload.customerPhone.trim(),
        payload.storeCode.trim()
      );

      if (orderRecord == null) {
        throw new ReturnApiException(
          404,
          'ORDER_NOT_FOUND',
          'Không tìm thấy đơn hàng hoặc thông tin khách hàng không khớp.'
        );
      }

      Set<String> requestedSkus = new Set<String>();

      for (ReturnApiRequest.ReturnApiLineRequest line : payload.lines) {
        requestedSkus.add(normalizeCode(line.sku));
      }

      Map<String, OrderItem> orderItemsBySku = ReturnApiSelector.selectOrderItemsBySku(
        orderRecord.Id,
        requestedSkus
      );

      CreateReturnInput serviceInput = buildServiceInput(
        payload,
        orderRecord,
        orderItemsBySku
      );

      CreateReturnResult serviceResult = ReturnIntakeService.createReturn(
        serviceInput
      );

      if (serviceResult.success != true) {
        existingRequest = ReturnApiSelector.selectByExternalRequestId(
          externalRequestId
        );

        if (existingRequest != null) {
          writeJson(response, 200, buildCreateResponse(existingRequest));
          return;
        }

        writeJson(
          response,
          400,
          buildBusinessError(
            serviceResult.code,
            serviceResult.message,
            payload.lines
          )
        );
        return;
      }

      Return_Request__c createdRequest = ReturnApiSelector.selectById(
        serviceResult.returnRequestId
      );

      writeJson(response, 201, buildCreateResponse(createdRequest));
    } catch (ReturnApiException exceptionRecord) {
      writeJson(
        response,
        exceptionRecord.statusCode,
        buildErrorResponse(
          exceptionRecord.errorCode,
          exceptionRecord.getMessage()
        )
      );
    } catch (Exception exceptionRecord) {
      String traceId = generateTraceId();

      System.debug(
        LoggingLevel.ERROR,
        'REQ-16 | Create API failed' +
          ' | traceId=' +
          traceId +
          ' | type=' +
          exceptionRecord.getTypeName() +
          ' | message=' +
          exceptionRecord.getMessage() +
          ' | stack=' +
          exceptionRecord.getStackTraceString()
      );

      writeJson(response, 500, buildInternalError(traceId));
    }
  }

  @HttpGet
  global static void lookupReturn() {
    RestResponse response = RestContext.response;

    try {
      String requestNumber = getPathIdentifier(RestContext.request.requestURI);

      if (String.isBlank(requestNumber)) {
        throw new ReturnApiException(
          400,
          'MISSING_FIELD',
          'Thiếu mã yêu cầu trả hàng.'
        );
      }

      Return_Request__c requestRecord = ReturnApiSelector.selectByRequestNumber(
        requestNumber
      );

      if (requestRecord == null) {
        throw new ReturnApiException(
          404,
          'REQUEST_NOT_FOUND',
          'Không tìm thấy yêu cầu trả hàng.'
        );
      }

      writeJson(response, 200, buildLookupResponse(requestRecord));
    } catch (ReturnApiException exceptionRecord) {
      writeJson(
        response,
        exceptionRecord.statusCode,
        buildErrorResponse(
          exceptionRecord.errorCode,
          exceptionRecord.getMessage()
        )
      );
    } catch (Exception exceptionRecord) {
      String traceId = generateTraceId();

      System.debug(
        LoggingLevel.ERROR,
        'REQ-16 | Lookup API failed' +
          ' | traceId=' +
          traceId +
          ' | type=' +
          exceptionRecord.getTypeName() +
          ' | message=' +
          exceptionRecord.getMessage()
      );

      writeJson(response, 500, buildInternalError(traceId));
    }
  }

  private static ReturnApiRequest parseRequest(RestRequest request) {
    if (
      request == null ||
      request.requestBody == null ||
      String.isBlank(request.requestBody.toString())
    ) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'Request body is required.'
      );
    }

    try {
      return (ReturnApiRequest) JSON.deserialize(
        request.requestBody.toString(),
        ReturnApiRequest.class
      );
    } catch (JSONException exceptionRecord) {
      throw new ReturnApiException(
        400,
        'INVALID_VALUE',
        'Request body contains invalid JSON.'
      );
    }
  }

  private static void validateRequest(ReturnApiRequest payload) {
    if (payload == null) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'Request body is required.'
      );
    }

    if (String.isBlank(payload.externalRequestId)) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'externalRequestId is required.'
      );
    }

    if (payload.externalRequestId.trim().length() > 100) {
      throw new ReturnApiException(
        400,
        'INVALID_VALUE',
        'externalRequestId cannot exceed 100 characters.'
      );
    }

    String channel = normalizeCode(payload.channel);

    if (
      channel != SmartReturnConstants.SOURCE_POS &&
      channel != SmartReturnConstants.SOURCE_APP
    ) {
      throw new ReturnApiException(
        400,
        'INVALID_VALUE',
        'channel must be POS or APP.'
      );
    }

    if (String.isBlank(payload.orderNumber)) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'orderNumber is required.'
      );
    }

    if (String.isBlank(payload.customerPhone)) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'customerPhone is required.'
      );
    }

    if (String.isBlank(payload.storeCode)) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'storeCode is required.'
      );
    }

    if (payload.lines == null || payload.lines.isEmpty()) {
      throw new ReturnApiException(
        400,
        'MISSING_FIELD',
        'At least one return line is required.'
      );
    }

    Set<String> skus = new Set<String>();

    for (Integer index = 0; index < payload.lines.size(); index++) {
      ReturnApiRequest.ReturnApiLineRequest line = payload.lines[index];

      if (line == null || String.isBlank(line.sku)) {
        throw new ReturnApiException(
          400,
          'MISSING_FIELD',
          'sku is required at line ' + index + '.'
        );
      }

      String normalizedSku = normalizeCode(line.sku);

      if (skus.contains(normalizedSku)) {
        throw new ReturnApiException(
          400,
          'INVALID_VALUE',
          'A SKU cannot appear more than once.'
        );
      }
      skus.add(normalizedSku);

      if (line.quantity == null || line.quantity <= 0) {
        throw new ReturnApiException(
          400,
          'INVALID_VALUE',
          'quantity must be greater than 0 at line ' + index + '.'
        );
      }

      validateReason(line.reason, index);
      validateCondition(line.condition, index);
    }
  }

  private static void validateReason(String reason, Integer index) {
    String normalizedReason = normalizeApiReason(reason);

    Set<String> validReasons = new Set<String>{
      SmartReturnConstants.REASON_CODE_DEFECT,
      SmartReturnConstants.REASON_CODE_WRONG_ITEM,
      SmartReturnConstants.REASON_CODE_NOT_SATISFIED,
      SmartReturnConstants.REASON_CODE_CUSTOMER_DAMAGED
    };

    if (
      String.isBlank(normalizedReason) ||
      !validReasons.contains(normalizedReason)
    ) {
      throw new ReturnApiException(
        400,
        'INVALID_VALUE',
        'Invalid reason at line ' + index + '.'
      );
    }
  }

  private static void validateCondition(String condition, Integer index) {
    String normalizedCondition = normalizeCode(condition);

    Set<String> validConditions = new Set<String>{
      SmartReturnConstants.GOODS_CONDITION_SEALED,
      SmartReturnConstants.GOODS_CONDITION_OPENED,
      SmartReturnConstants.GOODS_CONDITION_USED
    };

    if (
      String.isBlank(normalizedCondition) ||
      !validConditions.contains(normalizedCondition)
    ) {
      throw new ReturnApiException(
        400,
        'INVALID_VALUE',
        'Invalid condition at line ' + index + '.'
      );
    }
  }

  private static CreateReturnInput buildServiceInput(
    ReturnApiRequest payload,
    Order orderRecord,
    Map<String, OrderItem> orderItemsBySku
  ) {
    CreateReturnInput input = new CreateReturnInput();
    input.orderId = orderRecord.Id;
    input.sourceChannel = normalizeCode(payload.channel);
    input.externalRequestId = payload.externalRequestId.trim();
    input.lines = new List<CreateReturnLineInput>();

    for (ReturnApiRequest.ReturnApiLineRequest apiLine : payload.lines) {
      String sku = normalizeCode(apiLine.sku);
      OrderItem orderItem = orderItemsBySku.get(sku);

      if (orderItem == null) {
        throw new ReturnApiException(
          400,
          'SKU_NOT_IN_ORDER',
          'SKU ' + apiLine.sku + ' does not belong to the order.'
        );
      }

      CreateReturnLineInput serviceLine = new CreateReturnLineInput();
      serviceLine.orderItemId = orderItem.Id;
      serviceLine.requestedQuantity = apiLine.quantity;
      serviceLine.reasonCode = normalizeApiReason(apiLine.reason);
      serviceLine.conditionCode = normalizeCode(apiLine.condition);
      input.lines.add(serviceLine);
    }

    return input;
  }

  private static ReturnApiResponse.CreateResponse buildCreateResponse(
    Return_Request__c requestRecord
  ) {
    ReturnApiResponse.CreateResponse response = new ReturnApiResponse.CreateResponse();

    response.requestNumber = requestRecord.Name;
    response.status = requestRecord.Status__c;
    response.approvalLevel = requestRecord.Required_Approval_Level__c;
    response.estimatedRefundAmount = requestRecord.Estimated_Refund_Amount__c;

    for (
      Return_Request_Line__c line : ReturnApiSelector.selectLines(
        requestRecord.Id
      )
    ) {
      ReturnApiResponse.CreateLineResponse lineResponse = new ReturnApiResponse.CreateLineResponse();

      lineResponse.sku = line.Product__r.ProductCode;
      lineResponse.quantity = line.Requested_Quantity__c;
      lineResponse.unitPrice = line.Unit_Price_Paid__c;
      lineResponse.refundRate = line.Estimated_Refund_Rate__c == null
        ? null
        : line.Estimated_Refund_Rate__c / 100;
      lineResponse.refundAmount = line.Estimated_Refund_Amount__c;
      response.lines.add(lineResponse);
    }

    return response;
  }

  private static ReturnApiResponse.LookupResponse buildLookupResponse(
    Return_Request__c requestRecord
  ) {
    ReturnApiResponse.LookupResponse response = new ReturnApiResponse.LookupResponse();

    response.requestNumber = requestRecord.Name;
    response.status = requestRecord.Status__c;
    response.orderNumber = requestRecord.Order__r.OrderNumber;
    response.refundAmount = requestRecord.Actual_Refund_Amount__c != null
      ? requestRecord.Actual_Refund_Amount__c
      : requestRecord.Estimated_Refund_Amount__c;

    for (
      Return_Request_Line__c line : ReturnApiSelector.selectLines(
        requestRecord.Id
      )
    ) {
      ReturnApiResponse.LookupLineResponse lineResponse = new ReturnApiResponse.LookupLineResponse();

      lineResponse.sku = line.Product__r.ProductCode;
      lineResponse.quantity = line.Requested_Quantity__c;
      lineResponse.inspectionResult = null;
      lineResponse.refundAmount = line.Estimated_Refund_Amount__c;
      response.lines.add(lineResponse);
    }

    buildHistory(requestRecord, response.history);
    return response;
  }

  private static void buildHistory(
    Return_Request__c requestRecord,
    List<ReturnApiResponse.HistoryResponse> responseHistory
  ) {
    List<Return_Request__History> histories = ReturnApiSelector.selectStatusHistory(
      requestRecord.Id
    );

    if (histories.isEmpty()) {
      responseHistory.add(
        new ReturnApiResponse.HistoryResponse(
          requestRecord.Status__c,
          requestRecord.CreatedDate
        )
      );
      return;
    }

    String firstStatus = String.valueOf(histories[0].OldValue);

    if (String.isNotBlank(firstStatus)) {
      responseHistory.add(
        new ReturnApiResponse.HistoryResponse(
          firstStatus,
          requestRecord.CreatedDate
        )
      );
    }

    for (Return_Request__History history : histories) {
      String newStatus = String.valueOf(history.NewValue);

      if (String.isBlank(newStatus)) {
        continue;
      }

      responseHistory.add(
        new ReturnApiResponse.HistoryResponse(newStatus, history.CreatedDate)
      );
    }
  }

  private static ReturnApiResponse.ErrorResponse buildBusinessError(
    String code,
    String message,
    List<ReturnApiRequest.ReturnApiLineRequest> inputLines
  ) {
    ReturnApiResponse.ErrorResponse response = buildErrorResponse(
      'VALIDATION_FAILED',
      'Yêu cầu không hợp lệ.'
    );

    ReturnApiResponse.ErrorDetail detail = new ReturnApiResponse.ErrorDetail();

    detail.sku = inputLines == null || inputLines.isEmpty()
      ? null
      : inputLines[0].sku;
    detail.code = mapBusinessErrorCode(code);
    detail.message = message;
    response.details.add(detail);

    return response;
  }

  private static ReturnApiResponse.ErrorResponse buildErrorResponse(
    String errorCode,
    String message
  ) {
    ReturnApiResponse.ErrorResponse response = new ReturnApiResponse.ErrorResponse();
    response.errorCode = errorCode;
    response.message = message;
    return response;
  }

  private static ReturnApiResponse.ErrorResponse buildInternalError(
    String traceId
  ) {
    ReturnApiResponse.ErrorResponse response = buildErrorResponse(
      'INTERNAL_ERROR',
      'Đã xảy ra lỗi hệ thống.'
    );
    response.traceId = traceId;
    return response;
  }

  private static String mapBusinessErrorCode(String serviceCode) {
    Map<String, String> apiCodes = new Map<String, String>{
      'CATEGORY_NOT_RETURNABLE' => 'NOT_RETURNABLE',
      'RETURN_PERIOD_EXPIRED' => 'RETURN_WINDOW_EXPIRED',
      'QUANTITY_EXCEEDED' => 'QUANTITY_EXCEEDED',
      'INVALID_ORDER_ITEM' => 'SKU_NOT_IN_ORDER'
    };

    return apiCodes.containsKey(serviceCode)
      ? apiCodes.get(serviceCode)
      : serviceCode;
  }

  private static String normalizeApiReason(String reason) {
    String normalizedReason = normalizeCode(reason);

    if (normalizedReason == 'CUSTOMER_DAMAGE') {
      return SmartReturnConstants.REASON_CODE_CUSTOMER_DAMAGED;
    }

    return normalizedReason;
  }

  private static String getPathIdentifier(String requestUri) {
    if (String.isBlank(requestUri)) {
      return null;
    }

    String marker = '/smartreturn/v1/return-requests/';
    Integer markerPosition = requestUri.indexOf(marker);

    if (markerPosition < 0) {
      return null;
    }

    String identifier = requestUri.substring(markerPosition + marker.length());

    Integer queryPosition = identifier.indexOf('?');

    if (queryPosition >= 0) {
      identifier = identifier.substring(0, queryPosition);
    }

    return EncodingUtil.urlDecode(identifier, 'UTF-8');
  }

  private static String normalizeCode(String value) {
    return String.isBlank(value) ? null : value.trim().toUpperCase();
  }

  private static String generateTraceId() {
    return EncodingUtil.convertToHex(Crypto.generateAesKey(128))
      .substring(0, 16);
  }

  private static void writeJson(
    RestResponse response,
    Integer statusCode,
    Object body
  ) {
    response.statusCode = statusCode;
    response.addHeader('Content-Type', 'application/json');
    response.responseBody = Blob.valueOf(JSON.serialize(body));
  }
}
