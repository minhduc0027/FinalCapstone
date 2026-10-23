// Temporary selector class to allow for the use of DbQueryService in ReturnRequestService. This is a temporary solution until we can refactor the service to not require this.
public with sharing class ReturnRequestSelector {
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
      'Return_Request__c',
      new List<String>{
        'Id',
        'Name',
        'Status__c',
        'Order__c',
        'Order__r.OrderNumber',
        'Store__c',
        'Store__r.Store_Code__c',
        'Actual_Refund_Amount__c',
        'Inspection_Completed_At__c'
      },
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
      'Return_Request_Line__c',
      new List<String>{ 'Id', 'Return_Request__c', 'Inspection_Result__c' },
      'Return_Request__c IN :ids',
      new Map<String, Object>{ 'ids' => requestIds },
      false,
      10000,
      'Id'
    );
  }

  public static List<Return_Request__c> waitingForRefund(Integer size) {
    DbQueryPlan plan = new DbQueryPlan();
    plan.selectFrom = 'SELECT Id FROM Return_Request__c';
    plan.orderField = 'Inspection_Completed_At__c';
    plan.whereParts.add(
      'Status__c = \'INSPECTING\' AND Inspection_Completed_At__c != NULL'
    );
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
