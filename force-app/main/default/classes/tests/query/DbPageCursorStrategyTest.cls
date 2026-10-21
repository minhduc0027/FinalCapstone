@IsTest
private class DbPageCursorStrategyTest {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }
  @IsTest
  static void nativeCursorResumesAndHandlesEnd() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(
      DbPageRequest.PAGE_CURSOR
    );

    DbQueryResult first = DbQueryService.execute(request, 2);

    QueryTestSupport.assertCursorContinuation(first, 0);
    Assert.areEqual(2, first.records.size());
    Assert.areEqual(TOTAL_ACCOUNTS, first.totalRecords);
    Assert.areEqual(2, first.nextPosition);

    DbQueryResult second = DbQueryService.fetchPage(
      first.cursor,
      first.nextPosition,
      2,
      2
    );

    QueryTestSupport.assertCursorContinuation(second, first.nextPosition);
    Assert.areEqual(2, second.records.size());
    QueryTestSupport.assertNoOverlap(first.records, second.records);

    DbQueryResult last = DbQueryService.fetchPage(
      second.cursor,
      second.nextPosition,
      2,
      2
    );

    Assert.areEqual(1, last.records.size());
    Assert.areEqual(false, last.hasNext);
    Assert.areEqual(
      null,
      last.nextPosition,
      'Final cursor page must not expose nextPosition'
    );
    QueryTestSupport.assertNoOverlap(second.records, last.records);

    DbQueryResult terminal = DbQueryService.fetchPage(
      first.cursor,
      first.totalRecords,
      2,
      2
    );

    Assert.areEqual(0, terminal.records.size());
    Assert.areEqual(false, terminal.hasNext);
    Assert.areEqual(null, terminal.nextPosition);
    Test.stopTest();
  }
  @IsTest
  static void cursorDeletionAndExactPage() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(
      DbPageRequest.PAGE_CURSOR
    );
    request.pageSize = TOTAL_ACCOUNTS;

    DbQueryResult exact = DbQueryService.execute(request, TOTAL_ACCOUNTS);

    Assert.areEqual(TOTAL_ACCOUNTS, exact.records.size());
    Assert.areEqual(false, exact.hasNext);
    Assert.areEqual(null, exact.nextPosition);

    request.pageSize = 2;

    DbQueryResult first = DbQueryService.execute(request, 2);
    List<Account> ordered = [
      SELECT Id
      FROM Account
      WHERE Name LIKE 'Page %'
      ORDER BY Id
    ];

    delete ordered[2];

    DbQueryResult next = DbQueryService.fetchPage(
      first.cursor,
      first.nextPosition,
      2,
      2
    );

    Set<Id> expectedRemainingIds = new Set<Id>{ ordered[3].Id, ordered[4].Id };

    Assert.areEqual(
      expectedRemainingIds,
      QueryTestSupport.idsOf(next.records),
      'Cursor must skip the deleted record and return remaining live records'
    );
    Assert.areEqual(false, next.hasNext);
    Assert.areEqual(null, next.nextPosition);

    QueryTestSupport.assertCursorPositionRejected(
      first.cursor,
      first.totalRecords + 1,
      'position'
    );

    QueryTestSupport.assertCursorPageSizeRejected(first.cursor, 2001);
    Test.stopTest();
  }
  @IsTest
  static void cursorRejectsInvalidInputs() {
    Test.startTest();
    DbQueryResult first = DbQueryService.execute(
      QueryTestSupport.newRequest(DbPageRequest.PAGE_CURSOR),
      2
    );

    try {
      DbQueryService.fetchPage(null, 0, 2, 2);
      Assert.isTrue(false, 'Expected null cursor rejection');
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage().contains('Pagination cursor is required'),
        expected.getMessage()
      );
    }

    for (Integer invalidPosition : new List<Integer>{ null, -1 }) {
      QueryTestSupport.assertCursorPositionRejected(
        first.cursor,
        invalidPosition,
        'position'
      );
    }

    for (Integer invalidSize : new List<Integer>{ 0, -1 }) {
      try {
        DbQueryService.fetchPage(first.cursor, 0, invalidSize, 2);
        Assert.isTrue(false, 'Expected invalid page size rejection');
      } catch (DbQueryException expected) {
        Assert.areNotEqual(null, expected.getMessage());
      }
    }
    Test.stopTest();
  }
}
