@IsTest
private class DbQueryFilterTest {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }
  @IsTest
  static void typedFiltersAreCoercedAndBound() {
    Test.startTest();
    List<FilterCondition> validFilters = new List<FilterCondition>{
      new FilterCondition('Name', 'IN', new List<Object>{ 'Page A', 'Page B' }),
      new FilterCondition(
        'AnnualRevenue',
        'IN',
        new List<Object>{ '100', '200' }
      ),
      new FilterCondition(
        'LastActivityDate',
        'IN',
        new List<Object>{ '2026-01-01' }
      ),
      new FilterCondition(
        'CreatedDate',
        'IN',
        new List<Object>{ '2026-01-01 00:00:00' }
      ),
      new FilterCondition(
        'OwnerId',
        'IN',
        new List<Object>{ UserInfo.getUserId() }
      ),
      new FilterCondition('IsDeleted', 'IN', new List<Object>{ false }),
      new FilterCondition('AnnualRevenue', '>=', '100'),
      new FilterCondition('LastActivityDate', '=', '2026-01-01'),
      new FilterCondition('CreatedDate', '<', '2026-01-01 00:00:00'),
      new FilterCondition('IsDeleted', '=', 'false'),
      new FilterCondition('Name', '!=', null),
      new FilterCondition('Name', ' like ', 'Page %')
    };

    for (FilterCondition filter : validFilters) {
      DbQueryRequest request = QueryTestSupport.newRequest(
        DbPageRequest.OFFSET
      );
      request.filters = new List<FilterCondition>{ filter };

      DbQueryResult result = DbQueryService.execute(request, 2);

      Assert.areEqual(
        2,
        result.bindCount,
        'Filter and LIMIT must remain bound'
      );
      Assert.isTrue(
        result.soql.contains(':b0'),
        'Expected filter bind in SOQL: ' + result.soql
      );
    }

    List<FilterCondition> invalidFilters = new List<FilterCondition>{
      new FilterCondition('Name', 'LIKE', null),
      new FilterCondition('Name', 'IN', 'not a list'),
      new FilterCondition('Name', 'IN', new List<Object>()),
      new FilterCondition('IsDeleted', '=', 'maybe'),
      new FilterCondition('AnnualRevenue', '=', 'not a number'),
      new FilterCondition('Name', '>', 'Page A'),
      new FilterCondition('OwnerId', 'LIKE', '%'),
      new FilterCondition('Name', 'DELETE', 'Page A'),
      new FilterCondition('', '=', 'Page A'),
      null
    };

    for (FilterCondition filter : invalidFilters) {
      DbQueryRequest request = QueryTestSupport.newRequest(
        DbPageRequest.OFFSET
      );
      request.filters = new List<FilterCondition>{ filter };

      QueryTestSupport.assertInvalidRequest(request, 'invalid filter');
    }

    DbQueryRequest duplicateField = QueryTestSupport.newRequest(
      DbPageRequest.OFFSET
    );
    duplicateField.fields.add('name');

    QueryTestSupport.assertInvalidRequest(
      duplicateField,
      'case-insensitive duplicate field'
    );

    DbQueryRequest blankField = QueryTestSupport.newRequest(
      DbPageRequest.OFFSET
    );
    blankField.fields = new List<String>{ ' ' };

    QueryTestSupport.assertInvalidRequest(blankField, 'blank SELECT field');
    Test.stopTest();
  }
  @IsTest
  static void multipleFiltersOnSameFieldAreSupported() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);

    request.filters = new List<FilterCondition>{
      new FilterCondition('Name', '!=', null),
      new FilterCondition('Name', 'LIKE', 'Page %')
    };

    DbQueryResult result = DbQueryService.execute(request, 2);

    Assert.areEqual(2, result.records.size());
    Assert.areEqual(3, result.bindCount, 'Two filters and LIMIT must be bound');
    Assert.isTrue(result.soql.contains(':b0'));
    Assert.isTrue(result.soql.contains(':b1'));
    Test.stopTest();
  }
}
