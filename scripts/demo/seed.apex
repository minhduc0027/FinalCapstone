// Run as an administrator. This script creates fixtures without sending payments.
Boolean dryRun = false;
Boolean sample = false;
Integer orderCount = sample ? 3 : 20;
String batch = 'SRDEMO-V1';
Savepoint checkpoint = Database.setSavepoint();
try {
  String prefix = batch + '%';
  Assert.areEqual(
    0,
    [SELECT COUNT() FROM Account WHERE Name LIKE :prefix],
    'Demo data already exists. Run cleanup before seeding again.'
  );

  Map<String, Store__c> stores = new Map<String, Store__c>();
  for (Store__c store : [
    SELECT Id, Store_Code__c, Store_Manager__c, Region_Manager__c
    FROM Store__c
    WHERE Store_Code__c IN ('HN-001', 'DN-001', 'HCM-001')
    WITH USER_MODE
  ])
    stores.put(store.Store_Code__c, store);
  Assert.areEqual(3, stores.size(), 'HN-001, DN-001 and HCM-001 must exist.');

  Map<String, User> actors = new Map<String, User>();
  for (User actor : [
    SELECT Id, Username
    FROM User
    WHERE
      IsActive = TRUE
      AND Username IN (
        'nvbac@hotmail.com',
        'chtbac@hotmail.com',
        'qlvbac@hotmail.com'
      )
    WITH USER_MODE
  ])
    actors.put(actor.Username, actor);
  Assert.areEqual(
    3,
    actors.size(),
    'The three active North demo users must exist.'
  );
  Assert.areEqual(
    actors.get('chtbac@hotmail.com').Id,
    stores.get('HN-001').Store_Manager__c,
    'HN-001 must be mapped to CHT Bac.'
  );
  Assert.areEqual(
    actors.get('qlvbac@hotmail.com').Id,
    stores.get('HN-001').Region_Manager__c,
    'HN-001 must be mapped to QLV Bac.'
  );
  Assert.isTrue(
    SmartReturnConfigService.isFeatureEnabled('Auto_Approval'),
    'Enable Auto_Approval to demonstrate the AUTO cases.'
  );
  Assert.isTrue(
    SmartReturnConfigService.getAutoApprovalLimit() >= 1800000 &&
      SmartReturnConfigService.getAutoApprovalLimit() < 5000000 &&
      SmartReturnConfigService.getStoreApprovalLimit() >= 5000000 &&
      SmartReturnConfigService.getStoreApprovalLimit() < 25000000,
    'The approval thresholds do not match the 5m/25m demo cases.'
  );
  Pricebook2 book = [
    SELECT Id, IsActive
    FROM Pricebook2
    WHERE IsStandard = TRUE
    LIMIT 1
  ];
  Assert.isTrue(
    book.IsActive,
    'Activate the standard price book before seeding.'
  );
  List<Group> accounting = [
    SELECT Id
    FROM Group
    WHERE Type = 'Queue' AND DeveloperName = 'SmartReturn_Accounting'
  ];
  Assert.areEqual(
    1,
    accounting.size(),
    'The SmartReturn_Accounting queue must exist.'
  );

  List<String> cases = new List<String>{
    'BAC_CHT_APPROVAL',
    'BAC_QLV_APPROVAL',
    'BAC_AUTO_INSPECT',
    'BAC_TIMEOUT_3',
    'BAC_RETRY_SUCCESS',
    'BAC_INVALID_AMOUNT',
    'TRUNG_REJECTED',
    'TRUNG_ACCOUNTING',
    'NAM_AWAITING_GOODS',
    'NAM_COMPLETED'
  };
  List<Integer> requestOrderIndexes = new List<Integer>{
    0,
    1,
    2,
    3,
    4,
    5,
    14,
    15,
    17,
    18
  };
  List<Decimal> prices = new List<Decimal>{
    5000000,
    25000000,
    1500000,
    1200000,
    1300000,
    1400000,
    800000,
    1900000,
    3500000,
    7500000,
    22000000,
    950000,
    1650000,
    2800000,
    1100000,
    1600000,
    4500000,
    1700000,
    1800000,
    2600000
  };
  if (sample) {
    while (cases.size() > 3)
      cases.remove(cases.size() - 1);
  }
  List<Account> customers = new List<Account>();
  List<Product2> products = new List<Product2>();
  for (Integer i = 0; i < orderCount; i++) {
    String ordinal = String.valueOf(i + 1);
    if (i < 9)
      ordinal = '0' + ordinal;
    Id ownerId = i < 14
      ? actors.get('nvbac@hotmail.com').Id
      : UserInfo.getUserId();
    customers.add(
      new Account(
        Name = batch + ' Khach ' + ordinal,
        Phone = '09000010' + ordinal,
        OwnerId = ownerId
      )
    );
    products.add(
      new Product2(
        Name = batch + ' Laptop ' + ordinal,
        ProductCode = batch + '-SKU-' + ordinal,
        Family = 'Laptop',
        IsActive = true
      )
    );
  }
  insert as user customers;
  insert as user products;
  List<PricebookEntry> entries = new List<PricebookEntry>();
  List<Order> orders = new List<Order>();
  for (Integer i = 0; i < orderCount; i++) {
    String storeCode = 'HN-001';
    if (i >= 14)
      storeCode = 'DN-001';
    if (i >= 17)
      storeCode = 'HCM-001';
    entries.add(
      new PricebookEntry(
        Pricebook2Id = book.Id,
        Product2Id = products[i].Id,
        UnitPrice = prices[i],
        IsActive = true
      )
    );
    orders.add(
      new Order(
        AccountId = customers[i].Id,
        OwnerId = customers[i].OwnerId,
        Store__c = stores.get(storeCode).Id,
        Pricebook2Id = book.Id,
        Status = 'Draft',
        EffectiveDate = Date.today().addDays(-3),
        Delivery_Date__c = Date.today().addDays(-2),
        Payment_Method__c = 'Cash',
        Description = batch + ' order ' + (i + 1)
      )
    );
  }
  insert as user entries;
  insert as user orders;
  List<OrderItem> items = new List<OrderItem>();
  for (Integer i = 0; i < orderCount; i++)
    items.add(
      new OrderItem(
        OrderId = orders[i].Id,
        PricebookEntryId = entries[i].Id,
        Quantity = 2,
        UnitPrice = prices[i]
      )
    );
  insert as user items;

  List<Return_Request__c> requests = new List<Return_Request__c>();
  List<String> approvalLevels = new List<String>{
    'CHT',
    'QLV',
    'AUTO',
    'AUTO',
    'AUTO',
    'AUTO',
    'AUTO',
    'AUTO',
    'AUTO',
    'AUTO'
  };
  for (Integer i = 0; i < cases.size(); i++) {
    Integer index = requestOrderIndexes[i];
    Boolean inspected = (i >= 3 && i <= 7) || i == 9;
    String status = i < 2 ? 'PENDING_APPROVAL' : 'INSPECTING';
    if (i == 6)
      status = 'REJECTED';
    if (i == 7)
      status = 'REFUND_FAILED';
    if (i == 8)
      status = 'AWAITING_GOODS';
    if (i == 9)
      status = 'COMPLETED';
    Decimal actualAmount;
    if (inspected)
      actualAmount = i == 6 ? 0 : prices[index];
    requests.add(
      new Return_Request__c(
        Order__c = orders[index].Id,
        Customer__c = customers[index].Id,
        Store__c = orders[index].Store__c,
        OwnerId = customers[index].OwnerId,
        External_Request_ID__c = batch + '-' + cases[i],
        Source_Channel__c = i == 8 ? 'APP' : 'POS',
        Status__c = status,
        Required_Approval_Level__c = approvalLevels[i],
        Estimated_Refund_Amount__c = prices[index],
        Actual_Refund_Amount__c = actualAmount,
        Inspection_Completed_At__c = inspected
          ? System.now().addMinutes(-5)
          : null,
        Rejection_Reason__c = i == 6
          ? 'Du lieu demo: san pham hu hong do tac dong ben ngoai.'
          : null,
        Internal_Notes__c = batch +
          ' | ' +
          cases[i] +
          ' | Synthetic demo fixture; no payment sent.'
      )
    );
  }
  insert as user requests;
  List<Return_Request_Line__c> lines = new List<Return_Request_Line__c>();
  for (Integer i = 0; i < requests.size(); i++) {
    Integer index = requestOrderIndexes[i];
    Boolean inspected = requests[i].Inspection_Completed_At__c != null;
    String inspectionResult;
    if (inspected)
      inspectionResult = i == 6 ? 'FAILED' : 'PASSED';
    lines.add(
      new Return_Request_Line__c(
        Return_Request__c = requests[i].Id,
        Order_Item__c = items[index].Id,
        Product__c = products[index].Id,
        Purchased_Quantity__c = 2,
        Requested_Quantity__c = 1,
        Unit_Price_Paid__c = prices[index],
        Return_Reason__c = 'DEFECT',
        Reported_Condition__c = 'SEALED',
        Is_Eligible__c = true,
        Eligibility_Code__c = 'ELIGIBLE',
        Eligibility_Reason__c = 'Du lieu demo: trong han tra hang.',
        Return_Deadline__c = Date.today().addDays(13),
        Estimated_Refund_Rate__c = 100,
        Estimated_Refund_Amount__c = prices[index],
        Inspection_Result__c = inspectionResult
      )
    );
  }
  insert as user lines;

  Map<Id, Order> storedOrders = new Map<Id, Order>(
    [SELECT Id, OrderNumber FROM Order WHERE Id IN :orders WITH USER_MODE]
  );
  Map<Id, Return_Request__c> storedRequests = new Map<Id, Return_Request__c>(
    [
      SELECT Id, Name, ApproverId__c
      FROM Return_Request__c
      WHERE Id IN :requests
      WITH USER_MODE
    ]
  );
  List<Refund_Transaction__c> history = new List<Refund_Transaction__c>();
  for (Integer i : new List<Integer>{ 7, 9 }) {
    if (i >= requests.size())
      continue;
    Return_Request__c request = requests[i];
    String reference = storedRequests.get(request.Id).Name;
    history.add(
      new Refund_Transaction__c(
        Return_Request__c = request.Id,
        Merchant_Reference__c = reference,
        Idempotency_Key__c = reference,
        Order_Number__c = storedOrders.get(request.Order__c).OrderNumber,
        Refund_Amount__c = request.Actual_Refund_Amount__c,
        Status__c = i == 7 ? 'FAILED' : 'SUCCEEDED',
        Attempt_Count__c = i == 7 ? 3 : 1,
        Last_Attempt_At__c = System.now().addHours(-1),
        Last_Error_Code__c = i == 7 ? 'RETRY_EXHAUSTED' : null,
        PayHub_Refund_Id__c = i == 9 ? batch + '-SYNTHETIC-SUCCESS' : null,
        Completed_At__c = System.now().addMinutes(-30)
      )
    );
  }
  insert as user history;
  if (!history.isEmpty()) {
    Task accountingTask = new Task(
      OwnerId = accounting[0].Id,
      WhatId = history[0].Id,
      Subject = batch + ' - Xu ly hoan tien thu cong',
      Status = 'Not Started',
      Priority = 'Normal',
      Description = 'Synthetic demo fixture: retry exhausted, no payment sent.'
    );
    insert as user accountingTask;
    history[0].Accounting_Task_Id__c = accountingTask.Id;
    update as user history[0];
  }

  List<Map<String, Object>> orderManifest = new List<Map<String, Object>>();
  for (Integer i = 0; i < orders.size(); i++)
    orderManifest.add(
      new Map<String, Object>{
        'index' => i + 1,
        'id' => orders[i].Id,
        'number' => storedOrders.get(orders[i].Id).OrderNumber,
        'storeId' => orders[i].Store__c,
        'unitPrice' => prices[i]
      }
    );
  List<Map<String, Object>> requestManifest = new List<Map<String, Object>>();
  for (Integer i = 0; i < requests.size(); i++)
    requestManifest.add(
      new Map<String, Object>{
        'case' => cases[i],
        'id' => requests[i].Id,
        'number' => storedRequests.get(requests[i].Id).Name,
        'status' => requests[i].Status__c,
        'orderIndex' => requestOrderIndexes[i] + 1,
        'approverId' => storedRequests.get(requests[i].Id).ApproverId__c
      }
    );
  if (dryRun)
    Database.rollback(checkpoint);
  System.debug(
    LoggingLevel.ERROR,
    'DEMO_RESULT=' +
    JSON.serialize(
      new Map<String, Object>{
        'batch' => batch,
        'dryRun' => dryRun,
        'sample' => sample,
        'orders' => orderManifest,
        'requests' => requestManifest,
        'refundPolicy' => new Map<String, Object>{
          'maxAttempts' => SmartReturnConfigService.getPayHubMaxRetries(),
          'retrySeconds' => SmartReturnConfigService.getPayHubRetryIntervalSeconds(),
          'timeoutSeconds' => SmartReturnConfigService.getPayHubMaxTimeoutSecond(),
          'sendingEnabled' => SmartReturnConfigService.isFeatureEnabled(
            'Send_PayHub'
          )
        }
      }
    )
  );
} catch (Exception error) {
  Database.rollback(checkpoint);
  throw error;
}
