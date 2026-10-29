// Deletes only this dataset. Purging custom records releases their unique keys.
Boolean purge = false;
String prefix = 'SRDEMO-V1%';
Savepoint checkpoint = Database.setSavepoint();
try {
  List<Account> customers = [
    SELECT Id, Name
    FROM Account
    WHERE Name LIKE :prefix
    WITH USER_MODE
  ];
  List<Product2> products = [
    SELECT Id
    FROM Product2
    WHERE ProductCode LIKE :prefix
    WITH USER_MODE
  ];
  List<Order> orders = [
    SELECT Id, Status
    FROM Order
    WHERE AccountId IN :customers
    WITH USER_MODE
  ];
  List<Contract> contracts = [
    SELECT Id, AccountId, Status
    FROM Contract
    WHERE AccountId IN :customers
    WITH USER_MODE
  ];
  List<Return_Request__c> requests = [
    SELECT Id
    FROM Return_Request__c
    WHERE Order__c IN :orders
    WITH USER_MODE
    FOR UPDATE
  ];
  List<Refund_Transaction__c> refunds = [
    SELECT Id, Status__c
    FROM Refund_Transaction__c
    WHERE Return_Request__c IN :requests
    WITH USER_MODE
    FOR UPDATE
  ];
  for (Refund_Transaction__c refund : refunds)
    Assert.isFalse(
      refund.Status__c == 'PROCESSING' || refund.Status__c == 'PENDING',
      'Wait for the active worker/callback before cleanup.'
    );
  List<Task> tasks = [
    SELECT Id
    FROM Task
    WHERE WhatId IN :requests OR WhatId IN :refunds
    WITH USER_MODE
  ];
  List<Integration_Log__c> logs = [
    SELECT Id
    FROM Integration_Log__c
    WHERE Refund_Transaction__c IN :refunds
    WITH USER_MODE
  ];
  List<Return_Request_Line__c> lines = [
    SELECT Id
    FROM Return_Request_Line__c
    WHERE Return_Request__c IN :requests
    WITH USER_MODE
  ];
  List<OrderItem> items = [
    SELECT Id
    FROM OrderItem
    WHERE OrderId IN :orders
    WITH USER_MODE
  ];
  List<PricebookEntry> entries = [
    SELECT Id
    FROM PricebookEntry
    WHERE Product2Id IN :products
    WITH USER_MODE
  ];
  delete as user tasks;
  delete as user logs;
  delete as user refunds;
  delete as user lines;
  delete as user requests;
  for (Order order : orders) order.Status = 'Draft';
  update as user orders;
  delete as user items;
  delete as user orders;
  delete as user entries;
  delete as user products;
  Set<Id> contractAccountIds = new Set<Id>();
  for (Contract contract : contracts) contractAccountIds.add(contract.AccountId);
  List<Account> archivedCustomers = new List<Account>();
  List<Account> deletableCustomers = new List<Account>();
  for (Account customer : customers) {
    if (contractAccountIds.contains(customer.Id)) {
      archivedCustomers.add(
        new Account(
          Id = customer.Id,
          Name = 'SRDEMO-ARCHIVED-' + String.valueOf(customer.Id)
        )
      );
    } else {
      deletableCustomers.add(customer);
    }
  }
  update as user archivedCustomers;
  delete as user deletableCustomers;
  if (purge) {
    List<Return_Request__c> deletedRequests = [
      SELECT Id
      FROM Return_Request__c
      WHERE External_Request_ID__c LIKE :prefix AND IsDeleted = TRUE
      ALL ROWS
    ];
    if (!deletedRequests.isEmpty()) {
      for (
        Database.EmptyRecycleBinResult result : Database.emptyRecycleBin(
          deletedRequests
        )
      )
        if (!result.isSuccess()) {
          String message = result.getErrors().isEmpty()
            ? 'unknown error'
            : result.getErrors()[0].getMessage();
          Assert.isTrue(
            message.contains('no recycle bin entry found'),
            'Could not purge a demo request: ' + message
          );
        }
    }
  }
  System.debug(
    LoggingLevel.ERROR,
    'DEMO_RESULT=' +
    JSON.serialize(
      new Map<String, Object>{
        'deletedOrders' => orders.size(),
        'deletedRequests' => requests.size(),
        'deletedRefunds' => refunds.size(),
        'archivedContractAccounts' => archivedCustomers.size(),
        'purged' => purge
      }
    )
  );
} catch (Exception error) {
  Database.rollback(checkpoint);
  throw error;
}
