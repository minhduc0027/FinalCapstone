@IsTest
private class DbOffsetStrategyTest {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }
  @IsTest
  static void offsetPagesAndCap() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    request.orderBy = 'Name';

    DbQueryResult first = DbQueryService.execute(request, 2);

    Assert.areEqual(
      DbPageRequest.OFFSET,
      first.strategy,
      'Expected OFFSET strategy'
    );
    Assert.areEqual(2, first.records.size());
    Assert.areEqual(true, first.hasNext);
    Assert.areEqual(2, first.nextOffset);
    Assert.areEqual('Page A', first.records[0].get('Name'));
    Assert.areEqual('Page B', first.records[1].get('Name'));
    Assert.isTrue(
      first.soql.contains('Name ASC, Id ASC'),
      'Expected deterministic Name + Id ordering: ' + first.soql
    );

    request.page.offsetSize = first.nextOffset;

    DbQueryResult second = DbQueryService.execute(request, 2);

    Assert.areEqual(2, second.records.size());
    Assert.areEqual(true, second.hasNext);
    Assert.areEqual(4, second.nextOffset);
    Assert.areEqual('Page C', second.records[0].get('Name'));
    Assert.areEqual('Page D', second.records[1].get('Name'));
    QueryTestSupport.assertNoOverlap(first.records, second.records);

    request.page.offsetSize = second.nextOffset;

    DbQueryResult last = DbQueryService.execute(request, 2);

    Assert.areEqual(1, last.records.size());
    Assert.areEqual('Page E', last.records[0].get('Name'));
    Assert.areEqual(false, last.hasNext);
    Assert.areEqual(
      null,
      last.nextOffset,
      'Final OFFSET page must not expose nextOffset'
    );
    QueryTestSupport.assertNoOverlap(second.records, last.records);

    // maxRows must cap the effective page size.
    request.page.offsetSize = 0;

    DbQueryResult capped = DbQueryService.execute(request, 1);

    Assert.areEqual(1, capped.records.size());
    Assert.areEqual(true, capped.hasNext);
    Assert.areEqual(1, capped.nextOffset);

    // The service must not mutate the request state.
    Assert.areEqual(
      0,
      request.page.offsetSize,
      'Request offsetSize must not be mutated'
    );
    Assert.areEqual(
      2,
      request.pageSize,
      'Requested pageSize must not be mutated by maxRows'
    );
    Test.stopTest();
  }
  @IsTest
  static void offsetAcceptsMaximumBoundary() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    request.page.offsetSize = 2000;

    DbQueryResult result = DbQueryService.execute(request, 2);

    Assert.areEqual(
      DbPageRequest.OFFSET,
      result.strategy,
      'OFFSET 2000 must be accepted'
    );
    Assert.areEqual(
      0,
      result.records.size(),
      'OFFSET 2000 should return no records for the current five-record fixture'
    );
    Assert.areEqual(
      false,
      result.hasNext,
      'No records should remain after OFFSET 2000 in this fixture'
    );
    Assert.areEqual(
      null,
      result.nextOffset,
      'An empty final page must not expose nextOffset'
    );
    Assert.isTrue(
      result.soql.contains('OFFSET'),
      'Generated SOQL must contain the OFFSET clause'
    );
    Test.stopTest();
  }
  @IsTest
  static void offsetHandlesExactAndOversizedPages() {
    Test.startTest();
    DbQueryRequest exact = QueryTestSupport.newRequest(DbPageRequest.OFFSET);
    exact.orderBy = 'Name';
    exact.pageSize = TOTAL_ACCOUNTS;

    DbQueryResult exactResult = DbQueryService.execute(exact, TOTAL_ACCOUNTS);

    Assert.areEqual(TOTAL_ACCOUNTS, exactResult.records.size());
    Assert.areEqual(false, exactResult.hasNext);
    Assert.areEqual(null, exactResult.nextOffset);

    DbQueryRequest oversized = QueryTestSupport.newRequest(
      DbPageRequest.OFFSET
    );
    oversized.orderBy = 'Name';
    oversized.pageSize = 10;

    DbQueryResult oversizedResult = DbQueryService.execute(oversized, 10);

    Assert.areEqual(TOTAL_ACCOUNTS, oversizedResult.records.size());
    Assert.areEqual(false, oversizedResult.hasNext);
    Assert.areEqual(null, oversizedResult.nextOffset);
    Test.stopTest();
  }
}
