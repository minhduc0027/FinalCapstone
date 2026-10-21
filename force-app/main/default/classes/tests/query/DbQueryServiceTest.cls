@IsTest
private class DbQueryServiceTest {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }
  @IsTest
  static void strategyIsNormalizedAndDefaultsToOffset() {
    Test.startTest();
    for (String strategy : new List<String>{ null, '', '   ' }) {
      DbQueryRequest request = QueryTestSupport.newRequest(strategy);

      DbQueryResult result = DbQueryService.execute(request, 2);

      Assert.areEqual(
        DbPageRequest.OFFSET,
        result.strategy,
        'Blank strategy must default to OFFSET'
      );
    }

    DbQueryRequest keyset = QueryTestSupport.newRequest(' keyset ');

    Assert.areEqual(
      DbPageRequest.KEYSET,
      DbQueryService.execute(keyset, 2).strategy,
      'Strategy must be trimmed and normalized'
    );
    Test.stopTest();
  }
  @IsTest
  static void locatorAndEmptyResults() {
    Test.startTest();
    DbQueryRequest locatorRequest = QueryTestSupport.newRequest(
      DbPageRequest.OFFSET
    );
    locatorRequest.page = null;
    locatorRequest.pageSize = null;

    Database.QueryLocatorIterator iterator = DbQueryService.queryLocator(
        locatorRequest
      )
      .iterator();

    Integer count = 0;

    while (iterator.hasNext()) {
      iterator.next();
      count++;
    }

    Assert.areEqual(TOTAL_ACCOUNTS, count);

    for (
      String strategy : new List<String>{
        DbPageRequest.OFFSET,
        DbPageRequest.KEYSET,
        DbPageRequest.PAGE_CURSOR
      }
    ) {
      DbQueryRequest request = QueryTestSupport.newRequest(strategy);
      request.filters[0].value = 'No matching account';

      DbQueryResult result = DbQueryService.execute(request, 2);

      Assert.areEqual(0, result.records.size());
      Assert.areEqual(false, result.hasNext);
      Assert.areEqual(null, result.nextOffset);
      Assert.areEqual(null, result.nextAfterId);
      Assert.areEqual(null, result.nextPosition);
    }
    Test.stopTest();
  }
  @IsTest
  static void rejectsInvalidPaginationRequests() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    request.page.offsetSize = -1;
    QueryTestSupport.assertInvalidRequest(request, 'negative offset');

    request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    request.page.offsetSize = 2001;
    QueryTestSupport.assertInvalidRequest(request, 'offset above 2000');

    request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'Industry';
    QueryTestSupport.assertInvalidRequest(
      request,
      'KEYSET configured picklist ordering'
    );

    request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.page.offsetSize = 1;
    QueryTestSupport.assertInvalidRequest(request, 'KEYSET with offset state');

    request = QueryTestSupport.newRequest(DbPageRequest.PAGE_CURSOR);
    request.page.offsetSize = 1;
    QueryTestSupport.assertInvalidRequest(
      request,
      'PAGE_CURSOR with offset state'
    );

    request = QueryTestSupport.newRequest(DbPageRequest.PAGE_CURSOR);
    request.page.afterId = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Page %'
      LIMIT 1
    ]
    .Id;
    QueryTestSupport.assertInvalidRequest(
      request,
      'PAGE_CURSOR with keyset state'
    );

    request = QueryTestSupport.newRequest(DbPageRequest.PAGE_CURSOR);
    request.pageSize = 2001;

    try {
      DbQueryService.execute(request, 2001);
      Assert.isTrue(false, 'Expected PAGE_CURSOR size rejection');
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage().contains('2000'),
        expected.getMessage()
      );
    }

    request = QueryTestSupport.newRequest('UNKNOWN');
    QueryTestSupport.assertInvalidRequest(request, 'unknown strategy');

    request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    request.pageSize = 0;
    QueryTestSupport.assertInvalidRequest(request, 'zero page size');

    QueryTestSupport.assertInvalidRequest(null, 'null request');

    try {
      DbQueryService.queryLocator(
        QueryTestSupport.newRequest(DbPageRequest.OFFSET)
      );
      Assert.isTrue(false, 'Expected QueryLocator pagination rejection');
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage().contains('batch scope'),
        expected.getMessage()
      );
    }
    Test.stopTest();
  }
  @IsTest
  static void rejectsInjectionAndKeepsValuesBound() {
    Test.startTest();
    DbQueryRequest fieldInjection = QueryTestSupport.newRequest(
      DbPageRequest.OFFSET
    );
    fieldInjection.fields = new List<String>{ 'Id FROM User' };

    QueryTestSupport.assertInvalidRequest(
      fieldInjection,
      'SELECT field injection'
    );

    DbQueryRequest valueInjection = QueryTestSupport.newRequest(
      DbPageRequest.KEYSET
    );
    valueInjection.filters[0].value = 'x\' OR Name != \'';

    DbQueryResult result = DbQueryService.execute(valueInjection, 2);

    Assert.areEqual(0, result.records.size());
    Assert.isTrue(
      !result.soql.contains('OR Name'),
      'Filter values must never be concatenated into SOQL'
    );
    Assert.areEqual(
      2,
      result.bindCount,
      'Filter value and LIMIT must remain bound'
    );
    Test.stopTest();
  }
  @IsTest
  static void exactPageAndBudget() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.pageSize = TOTAL_ACCOUNTS;

    DbQueryResult result = DbQueryService.execute(request, TOTAL_ACCOUNTS);

    Assert.areEqual(TOTAL_ACCOUNTS, result.records.size());
    Assert.areEqual(false, result.hasNext);
    Assert.areEqual(null, result.nextAfterId);

    try {
      DbQueryService.requireRows(50001);
      Assert.isTrue(false, 'Expected query-row budget rejection');
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage().contains('budget'),
        expected.getMessage()
      );
    }

    Assert.areEqual(1, DbQueryService.effectiveSize(10, 1));
    Assert.areEqual(2, DbQueryService.effectiveSize(2, 100));
    Test.stopTest();
  }
  @IsTest
  static void schemaValidation() {
    Test.startTest();
    List<Schema.SObjectType> types = SchemaHelper.getSObjectTypes(
      new List<String>{ ' Account ', 'Contact', 'account' }
    );

    Assert.areEqual(3, types.size());
    Assert.areEqual(types[0], types[2]);

    Set<String> accessible = SchemaHelper.getAccessibleFields('Account');

    accessible.clear();

    Assert.isTrue(
      SchemaHelper.getAccessibleFields('Account').contains('Name'),
      'Caller mutation must not corrupt cached schema data'
    );

    for (
      List<String> names : new List<List<String>>{
        null,
        new List<String>(),
        new List<String>{ '' },
        new List<String>{ 'NotAnObject' }
      }
    ) {
      try {
        SchemaHelper.getSObjectTypes(names);
        Assert.isTrue(false, 'Expected invalid object rejection');
      } catch (DbQueryException expected) {
        Assert.areNotEqual(null, expected.getMessage());
      }
    }

    for (
      String path : new List<String>{
        null,
        '',
        'Account.Owner.Manager.Name',
        'Missing',
        'Name.Name',
        'Account.Missing',
        'Account..Name'
      }
    ) {
      try {
        SchemaHelper.resolveFieldPath('Contact', path);
        Assert.isTrue(false, 'Invalid path: ' + path);
      } catch (DbQueryException expected) {
        Assert.areNotEqual(null, expected.getMessage());
      }
    }

    Assert.areEqual(
      'Account.Owner.Name',
      SchemaHelper.normalizeFieldPath('Contact', 'account.owner.name')
    );
    Assert.areEqual(
      'Who.Name',
      SchemaHelper.normalizeFieldPath('Task', 'who.name')
    );
    Assert.areEqual(true, SchemaHelper.isFilterable('Account', 'Name'));
    Test.stopTest();
  }
}
