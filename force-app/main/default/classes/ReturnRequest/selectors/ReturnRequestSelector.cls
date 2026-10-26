public with sharing class ReturnRequestSelector {
  private static final String RETURN_REQUEST_OBJECT = 'Return_Request__c';
  private static final String RETURN_REQUEST_LINE_OBJECT = 'Return_Request_Line__c';
  private static final List<String> REQUEST_FIELDS = new List<String>{
    'Id',
    'Name',
    'Status__c',
    'Order__c',
    'Order__r.OrderNumber',
    'Store__c',
    'Store__r.Store_Code__c',
    'Actual_Refund_Amount__c',
    'Inspection_Completed_At__c'
  };
  private static final List<String> LINE_FIELDS = new List<String>{
    'Id',
    'Return_Request__c',
    'Inspection_Result__c'
  };

  private static final List<String> INSPECTION_LINE_FIELDS = new List<String>{
    'Id',
    'Return_Request__c',
    'Product__c',
    'Product__r.Name',
    'Order_Item__c',
    'Order_Item__r.UnitPrice',
    'Purchased_Quantity__c',
    'Requested_Quantity__c',
    'Unit_Price_Paid__c',
    'Reported_Condition__c',
    'Return_Reason__c',
    'Inspection_Result__c',
    'Is_Eligible__c',
    'Eligibility_Code__c',
    'Eligibility_Reason__c',
    'Estimated_Refund_Rate__c',
    'Estimated_Refund_Amount__c'
  };

  public static List<Return_Request_Line__c> getReturnRequestLines(
    Id returnRequestId,
    Boolean lockRows
  ) {
    if (returnRequestId == null) {
      return new List<Return_Request_Line__c>();
    }

    return (List<Return_Request_Line__c>) selectRows(
      RETURN_REQUEST_LINE_OBJECT,
      INSPECTION_LINE_FIELDS,
      'Return_Request__c = :requestId',
      new Map<String, Object>{ 'requestId' => returnRequestId },
      lockRows,
      1000,
      'Id'
    );
  }

  private static List<SObject> selectRows(
    String objectName,
    List<String> fields,
    String condition,
    Map<String, Object> binds,
    Boolean lockRows,
    Integer cap,
    String orderBy
  ) {
    DbQueryRequest request = new DbQueryRequest();
    request.objectName = objectName;
    request.fields = fields;
    request.orderBy = orderBy;

    DbQueryPlan plan = DbQueryCompiler.compile(request);
    if (condition != null) {
      plan.whereParts.add(condition);
    }
    plan.binds.putAll(binds);
    plan.binds.put('refundRowLimit', cap + 1);

    DbQueryService.requireRows(cap + 1);

    List<String> parts = new List<String>();
    if (lockRows) {
      parts.add(plan.selectFrom);
      if (!plan.whereParts.isEmpty()) {
        parts.add(
          String.join(
            new List<String>{ 'WHERE', String.join(plan.whereParts, ' AND ') },
            ' '
          )
        );
      }
    } else {
      parts.add(plan.toSoql());
    }
    parts.add('LIMIT :refundRowLimit');
    if (lockRows)
      parts.add('FOR UPDATE');

    DbQueryResult result = DbQueryService.queryPage(
      plan,
      String.join(parts, ' '),
      cap
    );

    if (result.hasNext) {
      throw new SelectorException(
        String.join(
          new List<String>{
            'Query returned more than',
            String.valueOf(cap),
            'rows, please refine your query'
          },
          ' '
        )
      );
    }

    return result.records;
  }

  public static Map<Id, Return_Request__c> byIds(
    Set<Id> ids,
    Boolean lockRows
  ) {
    if (ids == null || ids.isEmpty()) {
      return new Map<Id, Return_Request__c>();
    }
    List<Return_Request__c> rows = (List<Return_Request__c>) selectRows(
      RETURN_REQUEST_OBJECT,
      REQUEST_FIELDS,
      'Id IN :ids',
      new Map<String, Object>{ 'ids' => ids },
      lockRows,
      ids.size(),
      'Id'
    );
    return new Map<Id, Return_Request__c>(rows);
  }

  public static List<Return_Request_Line__c> lines(Set<Id> requestIds) {
    return (List<Return_Request_Line__c>) selectRows(
      RETURN_REQUEST_LINE_OBJECT,
      LINE_FIELDS,
      'Return_Request__c IN :ids',
      new Map<String, Object>{ 'ids' => requestIds },
      false,
      10000,
      'Id'
    );
  }

  public static List<Return_Request__c> waitingForRefund(Integer size) {
    DbQueryPlan plan = new DbQueryPlan();
    plan.selectFrom = String.join(
      new List<String>{ 'SELECT Id FROM', RETURN_REQUEST_OBJECT },
      ' '
    );
    plan.orderField = 'Inspection_Completed_At__c';
    plan.whereParts.add('Status__c = :inspectingStatus');
    plan.whereParts.add('Inspection_Completed_At__c != NULL');
    plan.binds.put('inspectingStatus', SmartReturnConstants.STATUS_INSPECTING);
    plan.binds.put('rowLimit', size + 1);
    return (List<Return_Request__c>) DbQueryService.queryPage(
        plan,
        String.join(new List<String>{ plan.toSoql(), 'LIMIT :rowLimit' }, ' '),
        size
      )
      .records;
  }

  public class SelectorException extends Exception {
  }
}
