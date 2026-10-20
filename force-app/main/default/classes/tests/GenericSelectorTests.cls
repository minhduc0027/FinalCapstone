@IsTest
private class GenericSelectorTests {
  @TestSetup
  static void setupData() {
    insert new List<Account>{
      new Account(
        Name = 'Alpha Corp',
        AnnualRevenue = 1000,
        NumberOfEmployees = 10,
        Phone = '0900000001',
        Website = 'https://alpha.example'
      ),
      new Account(
        Name = 'Beta Corp',
        AnnualRevenue = 2000,
        NumberOfEmployees = 20,
        Phone = '0900000002',
        Website = 'https://beta.example'
      ),
      new Account(
        Name = 'Gamma Corp',
        AnnualRevenue = 3000,
        NumberOfEmployees = 30,
        Phone = '0900000003',
        Website = 'https://gamma.example'
      )
    };
  }

  private static ReportRequest baseRequest() {
    ReportRequest request = new ReportRequest();
    request.objectName = 'Account';
    request.fields = new List<String>{
      'Id',
      'Name',
      'AnnualRevenue',
      'NumberOfEmployees'
    };
    request.filters = new List<FilterCondition>();
    request.orderByFields = new List<String>();
    request.orderDesc = false;
    request.limitSize = 100;

    return request;
  }

  private static void assertConfigException(
    String expectedMessage,
    ReportRequest request,
    Integer maxRows
  ) {
    try {
      GenericSelector.selectRecords(request, maxRows);

      System.assert(
        false,
        'Expected ConfigReportException containing: ' + expectedMessage
      );
    } catch (ConfigReportException ex) {
      System.assert(
        ex.getMessage().contains(expectedMessage),
        'Actual exception: ' + ex.getMessage()
      );
    }
  }

  @IsTest
  static void selectRecords_shouldReturnMatchingAccounts() {
    ReportRequest request = baseRequest();

    request.filters.add(new FilterCondition('Name', 'LIKE', '%Corp'));

    request.orderByFields.add('Name');
    request.limitSize = 10;

    Test.startTest();

    ReportResult result = GenericSelector.selectRecords(request, 10);

    Test.stopTest();

    System.assertEquals(3, result.records.size());

    System.assertEquals(false, result.truncated);

    System.assertEquals(
      2,
      result.bindCount,
      'Expected one filter bind and one LIMIT bind.'
    );

    System.assert(
      result.soql.contains('SELECT Id, Name, AnnualRevenue, NumberOfEmployees')
    );

    System.assert(result.soql.contains('WHERE Name LIKE :b0'));

    System.assert(result.soql.contains('ORDER BY Name ASC'));

    System.assert(result.soql.endsWith('LIMIT :limitSize'));

    System.assertEquals(
      'Alpha Corp',
      String.valueOf(result.records[0].get('Name'))
    );
  }

  @IsTest
  static void selectRecords_shouldUseBackwardCompatibleOrderBy() {
    ReportRequest request = baseRequest();

    request.orderBy = 'Name';
    request.orderByFields.clear();
    request.orderDesc = true;
    request.limitSize = 2;

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(2, result.records.size());

    System.assert(result.soql.contains('ORDER BY Name DESC'));

    System.assertEquals(
      'Gamma Corp',
      String.valueOf(result.records[0].get('Name'))
    );
  }

  @IsTest
  static void selectRecords_shouldCapLimitAtMaxRows() {
    ReportRequest request = baseRequest();

    request.orderByFields.add('Name');
    request.limitSize = 500;

    ReportResult result = GenericSelector.selectRecords(request, 2);

    System.assertEquals(2, result.records.size());

    System.assertEquals(
      true,
      result.truncated,
      'Result should indicate requested limit was capped.'
    );

    System.assertEquals(1, result.bindCount);
  }

  @IsTest
  static void selectRecords_shouldUseDefaultLimit() {
    ReportRequest request = baseRequest();

    request.limitSize = null;
    request.orderByFields.add('Name');

    ReportResult result = GenericSelector.selectRecords(request, 200);

    System.assertEquals(3, result.records.size());

    System.assertEquals(false, result.truncated);
  }

  @IsTest
  static void selectRecords_shouldSupportStringInFilter() {
    ReportRequest request = baseRequest();

    request.filters.add(
      new FilterCondition(
        'Name',
        'IN',
        new List<String>{ 'Alpha Corp', 'Gamma Corp' }
      )
    );

    request.orderByFields.add('Name');

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(2, result.records.size());

    System.assertEquals('Alpha Corp', result.records[0].get('Name'));

    System.assertEquals('Gamma Corp', result.records[1].get('Name'));
  }

  @IsTest
  static void selectRecords_shouldSupportStringNotInFilter() {
    ReportRequest request = baseRequest();

    request.filters.add(
      new FilterCondition(
        'Name',
        'NOT IN',
        new Set<String>{ 'Alpha Corp', 'Beta Corp' }
      )
    );

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(1, result.records.size());

    System.assertEquals('Gamma Corp', result.records[0].get('Name'));
  }

  @IsTest
  static void selectRecords_shouldSupportIdCollection() {
    List<Account> accounts = [
      SELECT Id, Name
      FROM Account
      WHERE Name IN ('Alpha Corp', 'Beta Corp')
      ORDER BY Name
    ];

    ReportRequest request = baseRequest();

    request.filters.add(
      new FilterCondition(
        'Id',
        'IN',
        new Set<Id>{ accounts[0].Id, accounts[1].Id }
      )
    );

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(2, result.records.size());
  }

  @IsTest
  static void selectRecords_shouldConvertIntegerAndDecimalValues() {
    ReportRequest request = baseRequest();

    request.filters.add(new FilterCondition('NumberOfEmployees', '>=', '20'));

    request.filters.add(new FilterCondition('AnnualRevenue', '<=', '3000'));

    request.orderByFields.add('NumberOfEmployees');

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(2, result.records.size());

    System.assertEquals(20, result.records[0].get('NumberOfEmployees'));
  }

  @IsTest
  static void selectRecords_shouldConvertBooleanValue() {
    ReportRequest request = new ReportRequest();

    request.objectName = 'Account';
    request.fields = new List<String>{ 'Id', 'Name', 'IsDeleted' };

    request.filters = new List<FilterCondition>{
      new FilterCondition('IsDeleted', '=', 'false')
    };

    request.limitSize = 10;

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(3, result.records.size());
  }

  @IsTest
  static void selectRecords_shouldConvertDatetimeValue() {
    ReportRequest request = baseRequest();

    request.filters.add(
      new FilterCondition('CreatedDate', '<=', '2099-01-01T00:00:00.000Z')
    );

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(3, result.records.size());
  }

  @IsTest
  static void selectRecords_shouldConvertLocalDatetimeValue() {
    ReportRequest request = baseRequest();

    request.filters.add(
      new FilterCondition('CreatedDate', '<=', '2099-01-01 00:00:00')
    );

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(3, result.records.size());
  }

  @IsTest
  static void selectRecords_shouldSupportRelationshipFields() {
    ReportRequest request = new ReportRequest();

    request.objectName = 'Account';
    request.fields = new List<String>{ 'Id', 'Name', 'CreatedBy.Name' };

    request.filters = new List<FilterCondition>{
      new FilterCondition('CreatedBy.Name', '=', UserInfo.getName())
    };

    request.orderByFields = new List<String>{ 'CreatedBy.Name' };

    request.limitSize = 10;

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(3, result.records.size());

    System.assertNotEquals(null, result.records[0].getSObject('CreatedBy'));
  }

  @IsTest
  static void countRecords_shouldCountFilteredRecords() {
    ReportRequest request = baseRequest();

    request.filters.add(new FilterCondition('AnnualRevenue', '>=', 2000));

    Test.startTest();

    Integer recordCount = GenericSelector.countRecords(request);

    Test.stopTest();

    System.assertEquals(2, recordCount);
  }

  @IsTest
  static void countRecords_shouldCountWithoutFilters() {
    ReportRequest request = new ReportRequest();
    request.objectName = 'Account';

    Integer recordCount = GenericSelector.countRecords(request);

    System.assertEquals(3, recordCount);
  }

  @IsTest
  static void keysetPagination_shouldReturnNextAscendingPage() {
    Account beta = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Beta Corp'
      LIMIT 1
    ];

    ReportRequest request = baseRequest();

    request.fields = new List<String>{ 'Id', 'Name' };

    request.orderByFields = new List<String>{ 'Name', 'Id' };

    request.orderDesc = false;
    request.limitSize = 10;

    request.keysetCursor = new KeysetCursor(
      'Name',
      'Beta Corp',
      beta.Id,
      false
    );

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(1, result.records.size());

    System.assertEquals('Gamma Corp', result.records[0].get('Name'));

    System.assert(result.soql.contains('Name > :cursorPrimaryValue'));

    System.assert(result.soql.contains('Id > :cursorRecordId'));

    System.assert(result.soql.contains('ORDER BY Name ASC, Id ASC'));
  }

  @IsTest
  static void keysetPagination_shouldReturnNextDescendingPage() {
    Account beta = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Beta Corp'
      LIMIT 1
    ];

    ReportRequest request = baseRequest();

    request.fields = new List<String>{ 'Id', 'Name' };

    request.orderByFields = new List<String>{ 'Name', 'Id' };

    request.orderDesc = true;
    request.limitSize = 10;

    request.keysetCursor = new KeysetCursor('Name', 'Beta Corp', beta.Id, true);

    ReportResult result = GenericSelector.selectRecords(request, 10);

    System.assertEquals(1, result.records.size());

    System.assertEquals('Alpha Corp', result.records[0].get('Name'));

    System.assert(result.soql.contains('Name < :cursorPrimaryValue'));

    System.assert(result.soql.contains('ORDER BY Name DESC, Id DESC'));
  }

  @IsTest
  static void validation_shouldRejectInvalidRequestStructure() {
    assertConfigException('Report request must not be null', null, 10);

    ReportRequest blankObject = baseRequest();
    blankObject.objectName = ' ';

    assertConfigException(
      'Report object name must not be blank',
      blankObject,
      10
    );

    ReportRequest noFields = baseRequest();
    noFields.fields.clear();

    assertConfigException(
      'At least one SELECT field is required',
      noFields,
      10
    );

    ReportRequest badMaxRows = baseRequest();

    assertConfigException('maxRows must be greater than zero', badMaxRows, 0);
  }

  @IsTest
  static void validation_shouldRejectTooManyAndDuplicateFields() {
    ReportRequest tooMany = baseRequest();
    tooMany.fields.clear();

    for (Integer i = 0; i < 31; i++) {
      tooMany.fields.add('Name');
    }

    assertConfigException('cannot contain more than 30 fields', tooMany, 10);

    ReportRequest duplicateFields = baseRequest();
    duplicateFields.fields = new List<String>{ 'Id', 'Name', 'name' };

    assertConfigException('Duplicate SELECT field', duplicateFields, 10);

    ReportRequest blankField = baseRequest();
    blankField.fields = new List<String>{ 'Id', ' ' };

    assertConfigException('SELECT field must not be blank', blankField, 10);

    ReportRequest unknownField = baseRequest();
    unknownField.fields = new List<String>{ 'Id', 'Unknown_Field__c' };

    assertConfigException('Invalid field path', unknownField, 10);
  }

  @IsTest
  static void validation_shouldRejectInvalidFilters() {
    ReportRequest nullFilter = baseRequest();
    nullFilter.filters.add(null);

    assertConfigException('Filter at index 0 must not be null', nullFilter, 10);

    ReportRequest blankField = baseRequest();
    blankField.filters.add(new FilterCondition(' ', '=', 'Test'));

    assertConfigException(
      'Filter field at index 0 must not be blank',
      blankField,
      10
    );

    ReportRequest blankOperator = baseRequest();
    blankOperator.filters.add(new FilterCondition('Name', ' ', 'Test'));

    assertConfigException('Operator is required', blankOperator, 10);

    ReportRequest unsupportedOperator = baseRequest();
    unsupportedOperator.filters.add(
      new FilterCondition('Name', 'CONTAINS', 'Test')
    );

    assertConfigException('Unsupported operator', unsupportedOperator, 10);

    ReportRequest likeOnNumber = baseRequest();
    likeOnNumber.filters.add(
      new FilterCondition('NumberOfEmployees', 'LIKE', '20')
    );

    assertConfigException('Operator LIKE cannot be used', likeOnNumber, 10);

    ReportRequest comparisonOnBoolean = baseRequest();
    comparisonOnBoolean.filters.add(
      new FilterCondition('IsDeleted', '>', false)
    );

    assertConfigException('cannot be used with field', comparisonOnBoolean, 10);
  }

  @IsTest
  static void validation_shouldRejectInvalidCollectionValues() {
    ReportRequest nullCollection = baseRequest();
    nullCollection.filters.add(new FilterCondition('Name', 'IN', null));

    assertConfigException('requires a non-null collection', nullCollection, 10);

    ReportRequest scalarCollection = baseRequest();
    scalarCollection.filters.add(
      new FilterCondition('Name', 'IN', 'Alpha Corp')
    );

    assertConfigException('requires a list or set value', scalarCollection, 10);

    ReportRequest emptyCollection = baseRequest();
    emptyCollection.filters.add(
      new FilterCondition('Name', 'IN', new List<String>())
    );

    assertConfigException(
      'requires a non-empty collection',
      emptyCollection,
      10
    );
  }

  @IsTest
  static void validation_shouldRejectInvalidConvertedValues() {
    ReportRequest badBoolean = baseRequest();
    badBoolean.filters.add(
      new FilterCondition('IsDeleted', '=', 'not-a-boolean')
    );

    assertConfigException('Invalid Boolean value', badBoolean, 10);

    ReportRequest badInteger = baseRequest();
    badInteger.filters.add(
      new FilterCondition('NumberOfEmployees', '=', 'ABC')
    );

    assertConfigException('Invalid value', badInteger, 10);

    ReportRequest badDecimal = baseRequest();
    badDecimal.filters.add(new FilterCondition('AnnualRevenue', '=', 'ABC'));

    assertConfigException('Invalid value', badDecimal, 10);

    ReportRequest badId = baseRequest();
    badId.filters.add(new FilterCondition('Id', '=', 'INVALID-ID'));

    assertConfigException('Invalid Salesforce Id value', badId, 10);

    ReportRequest badDatetime = baseRequest();
    badDatetime.filters.add(
      new FilterCondition('CreatedDate', '=', 'not-a-datetime')
    );

    assertConfigException('Invalid value', badDatetime, 10);
  }

  @IsTest
  static void validation_shouldRejectInvalidOrdering() {
    ReportRequest duplicateOrder = baseRequest();
    duplicateOrder.orderByFields = new List<String>{ 'Name', 'name' };

    assertConfigException('Duplicate ORDER BY field', duplicateOrder, 10);

    ReportRequest blankOrder = baseRequest();
    blankOrder.orderByFields = new List<String>{ 'Name', ' ' };

    assertConfigException('ORDER BY field must not be blank', blankOrder, 10);

    ReportRequest invalidOrder = baseRequest();
    invalidOrder.orderByFields = new List<String>{ 'Unknown_Field__c' };

    assertConfigException('Invalid field path', invalidOrder, 10);
  }

  @IsTest
  static void validation_shouldRejectIncompleteCursor() {
    ReportRequest blankPrimary = baseRequest();
    blankPrimary.keysetCursor = new KeysetCursor();
    blankPrimary.keysetCursor.primaryField = ' ';
    blankPrimary.keysetCursor.primaryValue = 'Alpha';
    blankPrimary.keysetCursor.recordId = UserInfo.getUserId();

    assertConfigException('primary field must not be blank', blankPrimary, 10);

    ReportRequest nullPrimaryValue = baseRequest();
    nullPrimaryValue.keysetCursor = new KeysetCursor();

    nullPrimaryValue.keysetCursor.primaryField = 'Name';

    nullPrimaryValue.keysetCursor.recordId = UserInfo.getUserId();

    assertConfigException(
      'primary value must not be null',
      nullPrimaryValue,
      10
    );

    ReportRequest nullRecordId = baseRequest();
    nullRecordId.keysetCursor = new KeysetCursor();

    nullRecordId.keysetCursor.primaryField = 'Name';

    nullRecordId.keysetCursor.primaryValue = 'Alpha Corp';

    assertConfigException('record Id must not be null', nullRecordId, 10);

    ReportRequest nullDirection = baseRequest();
    nullDirection.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      UserInfo.getUserId(),
      null
    );

    assertConfigException('direction must be provided', nullDirection, 10);
  }

  @IsTest
  static void validation_shouldRejectInvalidKeysetConfiguration() {
    Account accountRecord = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    ReportRequest missingPrimarySelect = baseRequest();

    missingPrimarySelect.fields = new List<String>{ 'Id' };

    missingPrimarySelect.orderByFields = new List<String>{ 'Name', 'Id' };

    missingPrimarySelect.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      accountRecord.Id,
      false
    );

    assertConfigException(
      'must be included in SELECT fields',
      missingPrimarySelect,
      10
    );

    ReportRequest missingIdSelect = baseRequest();

    missingIdSelect.fields = new List<String>{ 'Name' };

    missingIdSelect.orderByFields = new List<String>{ 'Name', 'Id' };

    missingIdSelect.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      accountRecord.Id,
      false
    );

    assertConfigException('Field "Id" must be included', missingIdSelect, 10);

    ReportRequest wrongOrderCount = baseRequest();

    wrongOrderCount.fields = new List<String>{ 'Id', 'Name' };

    wrongOrderCount.orderByFields = new List<String>{ 'Name' };

    wrongOrderCount.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      accountRecord.Id,
      false
    );

    assertConfigException(
      'requires exactly two ORDER BY fields',
      wrongOrderCount,
      10
    );

    ReportRequest wrongPrimaryOrder = baseRequest();

    wrongPrimaryOrder.fields = new List<String>{ 'Id', 'Name', 'CreatedDate' };

    wrongPrimaryOrder.orderByFields = new List<String>{ 'CreatedDate', 'Id' };

    wrongPrimaryOrder.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      accountRecord.Id,
      false
    );

    assertConfigException(
      'first ORDER BY field must match',
      wrongPrimaryOrder,
      10
    );

    ReportRequest wrongTieBreaker = baseRequest();

    wrongTieBreaker.fields = new List<String>{ 'Id', 'Name', 'CreatedDate' };

    wrongTieBreaker.orderByFields = new List<String>{ 'Name', 'CreatedDate' };

    wrongTieBreaker.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      accountRecord.Id,
      false
    );

    assertConfigException(
      'second ORDER BY field must be Id',
      wrongTieBreaker,
      10
    );

    ReportRequest wrongDirection = baseRequest();

    wrongDirection.fields = new List<String>{ 'Id', 'Name' };

    wrongDirection.orderByFields = new List<String>{ 'Name', 'Id' };

    wrongDirection.orderDesc = true;

    wrongDirection.keysetCursor = new KeysetCursor(
      'Name',
      'Alpha Corp',
      accountRecord.Id,
      false
    );

    assertConfigException('direction must match', wrongDirection, 10);
  }

  @IsTest
  static void countValidation_shouldRejectInvalidRequests() {
    try {
      GenericSelector.countRecords(null);
      System.assert(false, 'Expected exception.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('Count request must not be null'));
    }

    ReportRequest request = new ReportRequest();

    request.objectName = ' ';

    try {
      GenericSelector.countRecords(request);
      System.assert(false, 'Expected exception.');
    } catch (ConfigReportException ex) {
      System.assert(
        ex.getMessage().contains('Count object name must not be blank')
      );
    }
  }
}
