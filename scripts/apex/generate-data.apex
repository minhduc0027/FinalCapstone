List<Return_Request__c> reqs = [
  SELECT Id
  FROM Return_Request__c
  WHERE
    Status__c = 'INSPECTING'
    AND Inspection_Completed_At__c = NULL
    AND Id NOT IN (
      SELECT Return_Request__c
      FROM Return_Request_Line__c
      WHERE Return_Request__c != NULL
    )
];

if (!reqs.isEmpty()) {
  Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Inspection Test Customer'];

  Store__c store = [
    SELECT Id
    FROM Store__c
    WHERE Store_Code__c = 'APP-PAGING-001'
    LIMIT 1
  ];

  Pricebook2 pb = [
    SELECT Id, IsActive
    FROM Pricebook2
    WHERE IsStandard = TRUE
    LIMIT 1
  ];

  if (!pb.IsActive) {
    pb.IsActive = true;

    update pb;
  }

  List<Product2> products = [
    SELECT Id, Name
    FROM Product2
    WHERE
      Name IN ('Test Product 1', 'Test Product 2', 'Test Product 3')
      AND IsActive = TRUE
    ORDER BY Name
  ];

  Set<Id> productIds = new Map<Id, Product2>(products).keySet();

  List<PricebookEntry> pbes = [
    SELECT Id, Product2Id, UnitPrice
    FROM PricebookEntry
    WHERE
      Pricebook2Id = :pb.Id
      AND Product2Id IN :productIds
      AND IsActive = TRUE
    ORDER BY Product2.Name
  ];

  Order ord = new Order(
    AccountId = acc.Id,
    EffectiveDate = Date.today(),
    Status = 'Draft',
    Store__c = store.Id,
    Pricebook2Id = pb.Id
  );

  insert ord;

  List<OrderItem> items = new List<OrderItem>();

  for (PricebookEntry pbe : pbes) {
    items.add(
      new OrderItem(
        OrderId = ord.Id,
        PricebookEntryId = pbe.Id,
        Quantity = 2,
        UnitPrice = pbe.UnitPrice
      )
    );
  }

  insert items;

  items = [
    SELECT Id, Product2Id, Quantity, UnitPrice
    FROM OrderItem
    WHERE OrderId = :ord.Id
  ];

  List<Return_Request_Line__c> lines = new List<Return_Request_Line__c>();

  for (Return_Request__c req : reqs) {
    for (OrderItem item : items) {
      lines.add(
        new Return_Request_Line__c(
          Return_Request__c = req.Id,
          Order_Item__c = item.Id,
          Product__c = item.Product2Id,
          Purchased_Quantity__c = item.Quantity,
          Requested_Quantity__c = 1,
          Unit_Price_Paid__c = item.UnitPrice,
          Return_Reason__c = 'DEFECT',
          Reported_Condition__c = 'SEALED'
        )
      );
    }
  }

  insert lines;

  System.debug('Inserted lines: ' + lines.size());
}
