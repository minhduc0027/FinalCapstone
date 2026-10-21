/** Invalid boundary handling and continuation after deleting the anchor row. */
@IsTest
private class DbKeysetBoundaryTest {
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }

  @IsTest
  static void rejectsUnsortableBeforeQuery() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'Description';
    assertRejected(request, 'not sortable');
  }
  @IsTest
  static void rejectsPicklistBeforeQuery() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'Industry';
    assertRejected(request, 'picklist order');
  }
  @IsTest
  static void rejectsValueWithoutId() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'Name';
    request.page.afterValue = 'Page A';
    assertRejected(request, 'requires afterId');
  }
  @IsTest
  static void rejectsValueOnIdOrder() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.page.afterValue = 'unused';
    request.page.afterId = [SELECT Id FROM Account LIMIT 1].Id;
    assertRejected(request, 'afterId only');
  }
  @IsTest
  static void rejectsMalformedNumericValue() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'AnnualRevenue';
    request.page.afterValue = 'not-a-number';
    request.page.afterId = [SELECT Id FROM Account LIMIT 1].Id;
    assertRejected(request, 'Invalid value');
  }
  @IsTest
  static void rejectsOffsetValue() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    request.page.afterValue = 'unused';
    assertRejected(request, 'keyset continuation');
  }
  @IsTest
  static void rejectsCursorValue() {
    DbQueryRequest request = QueryTestSupport.newRequest(
      DbPageRequest.PAGE_CURSOR
    );
    request.page.afterValue = 'unused';
    assertRejected(request, 'keyset continuation');
  }
  @IsTest
  static void continuesAfterDeletedAnchor() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'Name';
    Test.startTest();
    DbQueryResult first = DbQueryService.execute(request, 2);
    request.page.afterId = first.nextAfterId;
    request.page.afterValue = first.nextAfterValue;
    delete new Account(Id = first.nextAfterId);
    DbQueryResult second = DbQueryService.execute(request, 3);
    Test.stopTest();
    Assert.areEqual(2, second.records.size(), 'Request page size remains two');
    Assert.areEqual(
      'Page C',
      second.records[0].get('Name'),
      'Seek uses supplied value, not an anchor lookup'
    );
    Assert.areEqual(
      'Page D',
      second.records[1].get('Name'),
      'Ordering continues after deleted anchor'
    );
  }
  @IsTest
  static void keepsBoundaryValuesBound() {
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);
    request.orderBy = 'Name';
    request.page.afterId = [SELECT Id FROM Account LIMIT 1].Id;
    request.page.afterValue = 'Page A\' OR Name != \'';
    Test.startTest();
    DbQueryResult result = DbQueryService.execute(request, 2);
    Test.stopTest();
    Assert.isFalse(
      result.soql.contains((String) request.page.afterValue),
      'Boundary must be a bind, never interpolated'
    );
    Assert.isTrue(
      result.soql.contains('(Name = :'),
      'Composite boundary must remain grouped'
    );
  }
  private static void assertRejected(DbQueryRequest request, String message) {
    Test.startTest();
    Integer beforeQueries = Limits.getQueries();
    try {
      DbQueryService.execute(request, 2);
      Assert.fail('Expected keyset validation error: ' + message);
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage().contains(message),
        expected.getMessage()
      );
    }
    Assert.areEqual(
      beforeQueries,
      Limits.getQueries(),
      'Reject invalid input before executing SOQL'
    );
    Test.stopTest();
  }
}
