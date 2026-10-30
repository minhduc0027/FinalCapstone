public with sharing class RefundSelector {
  private static final String REFUND_TRANSACTION_OBJECT = 'Refund_Transaction__c';
  private static final List<String> FIELDS = new List<String>{
    'Id',
    'Name',
    'Return_Request__c',
    'Merchant_Reference__c',
    'Idempotency_Key__c',
    'Order_Number__c',
    'Refund_Amount__c',
    'Status__c',
    'PayHub_Refund_Id__c',
    'Attempt_Count__c',
    'Next_Retry_At__c',
    'Last_Attempt_At__c',
    'Last_Error_Code__c',
    'Last_Error_Message__c',
    'Completed_At__c',
    'Worker_Job_Id__c',
    'Accounting_Task_Id__c',
    'Provider_Processed_At__c',
    'Manual_Reference__c',
    'Manual_Completed_At__c',
    'Manual_Completed_By__c'
  };

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
      throw new DbQueryException(
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

  public static List<Refund_Transaction__c> byIds(
    Set<Id> ids,
    Boolean lockRows
  ) {
    if (ids == null || ids.isEmpty())
      return new List<Refund_Transaction__c>();

    return (List<Refund_Transaction__c>) selectRows(
      REFUND_TRANSACTION_OBJECT,
      FIELDS,
      'Id IN :ids',
      new Map<String, Object>{ 'ids' => ids },
      lockRows,
      ids.size(),
      'Id'
    );
  }

  public static List<Refund_Transaction__c> byMerchant(
    String reference,
    Boolean lockRows
  ) {
    return (List<Refund_Transaction__c>) selectRows(
      REFUND_TRANSACTION_OBJECT,
      FIELDS,
      'Merchant_Reference__c = :reference',
      new Map<String, Object>{ 'reference' => reference },
      lockRows,
      1,
      'Id'
    );
  }

  public static List<Refund_Transaction__c> forRequests(Set<Id> ids) {
    return (List<Refund_Transaction__c>) selectRows(
      REFUND_TRANSACTION_OBJECT,
      FIELDS,
      'Return_Request__c IN :ids',
      new Map<String, Object>{ 'ids' => ids },
      true,
      ids.size(),
      'Id'
    );
  }

  public static List<Refund_Transaction__c> due(
    Datetime nowValue,
    Integer intervalSeconds,
    Integer size
  ) {
    DbQueryPlan plan = new DbQueryPlan();
    plan.selectFrom = 'SELECT Id FROM ' + REFUND_TRANSACTION_OBJECT;
    plan.orderField = 'CreatedDate';
    plan.whereParts.add('Manual_Completed_At__c = NULL');
    plan.whereParts.add(
      String.join(
        new List<String>{
          '((Status__c = :queuedStatus AND (Next_Retry_At__c = NULL OR Next_Retry_At__c <= :nowValue))',
          'OR (Status__c = :processingStatus AND Last_Attempt_At__c <= :expired))'
        },
        ' '
      )
    );
    plan.binds.put('queuedStatus', RefundDomain.Status.QUEUED.name());
    plan.binds.put('processingStatus', RefundDomain.Status.PROCESSING.name());
    plan.binds.put('nowValue', nowValue);
    plan.binds.put('expired', nowValue.addSeconds(-intervalSeconds));
    plan.binds.put('rowLimit', size + 1);

    return (List<Refund_Transaction__c>) DbQueryService.queryPage(
        plan,
        String.join(new List<String>{ plan.toSoql(), 'LIMIT :rowLimit' }, ' '),
        size
      )
      .records;
  }

  public static Id accountingQueue() {
    List<Group> rows = (List<Group>) selectRows(
      'Group',
      new List<String>{ 'Id' },
      'Type = :queueType AND DeveloperName = :queueName',
      new Map<String, Object>{
        'queueType' => 'Queue',
        'queueName' => 'SmartReturn_Accounting'
      },
      false,
      1,
      'Id'
    );

    if (rows.isEmpty()) {
      throw new DbQueryException('Not found accounting queue for SmartReturn');
    }

    return rows[0].Id;
  }

  /** Locks the request fields needed for manual completion without requiring Order access. */
  public static Map<Id, Return_Request__c> requestsForManualCompletion(
    Set<Id> ids
  ) {
    if (ids == null || ids.isEmpty())
      return new Map<Id, Return_Request__c>();

    List<Return_Request__c> rows = (List<Return_Request__c>) selectRows(
      'Return_Request__c',
      new List<String>{
        'Id',
        'Status__c',
        'Store__c',
        'Store__r.Store_Code__c'
      },
      'Id IN :ids',
      new Map<String, Object>{ 'ids' => ids },
      true,
      ids.size(),
      'Id'
    );
    return new Map<Id, Return_Request__c>(rows);
  }

  public static List<Task> tasks(Set<Id> ids) {
    return (List<Task>) selectRows(
      'Task',
      new List<String>{ 'Id', 'Status' },
      'Id IN :ids',
      new Map<String, Object>{ 'ids' => ids },
      false,
      ids.size(),
      'Id'
    );
  }
}
