@IsTest
private class DbQueryTraversalTest {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }
  @IsTest
  static void singleRecordPagesTraverseWithoutGaps() {
    Test.startTest();
    for (
      String strategy : new List<String>{
        DbPageRequest.KEYSET,
        DbPageRequest.PAGE_CURSOR
      }
    ) {
      List<Id> actualIds = new List<Id>();
      Set<Id> uniqueIds = new Set<Id>();

      DbQueryRequest request = QueryTestSupport.newRequest(strategy);
      request.pageSize = 1;

      Database.PaginationCursor cursor;
      Integer position;
      Boolean more = true;
      Integer safetyCounter = 0;

      while (more) {
        Assert.isTrue(
          safetyCounter < 10,
          strategy + ' pagination failed to terminate'
        );

        DbQueryResult result;

        if (strategy == DbPageRequest.PAGE_CURSOR && cursor != null) {
          result = DbQueryService.fetchPage(cursor, position, 1, 1);
        } else {
          result = DbQueryService.execute(request, 1);
        }

        Assert.areEqual(1, result.records.size());

        Id recordId = result.records[0].Id;

        Assert.isTrue(
          uniqueIds.add(recordId),
          strategy + ' returned a duplicate record'
        );

        actualIds.add(recordId);
        more = result.hasNext;

        if (strategy == DbPageRequest.KEYSET) {
          request.page.afterId = result.nextAfterId;
        } else {
          cursor = result.cursor;
          position = result.nextPosition;
        }

        safetyCounter++;
      }

      Assert.areEqual(TOTAL_ACCOUNTS, uniqueIds.size());
      Assert.areEqual(TOTAL_ACCOUNTS, actualIds.size());
    }
    Test.stopTest();
  }
  @IsTest
  static void keysetAndCursorContinueWhenOffsetLimitIsReached() {
    Test.startTest();
    QueryTestSupport.insertDeepPageAccounts(2501);

    Integer pageSize = 500;

    // -------------------------------------------------------------------------
    // OFFSET reaches its continuation limit.
    // -------------------------------------------------------------------------

    DbQueryRequest offsetRequest = QueryTestSupport.deepPageRequest(
      DbPageRequest.OFFSET,
      pageSize
    );

    Integer offsetPages = 0;
    Integer offsetRecords = 0;
    DbQueryResult offsetResult;

    do {
      offsetResult = DbQueryService.execute(offsetRequest, pageSize);

      offsetRecords += offsetResult.records.size();
      offsetPages++;

      if (offsetResult.nextOffset != null) {
        offsetRequest.page.offsetSize = offsetResult.nextOffset;
      }
    } while (offsetResult.hasNext && offsetResult.nextOffset != null);

    Assert.areEqual(
      5,
      offsetPages,
      'OFFSET must reach the page beginning at offset 2000'
    );

    Assert.areEqual(
      2500,
      offsetRecords,
      'OFFSET can return records through the page beginning at offset 2000'
    );

    Assert.areEqual(
      true,
      offsetResult.hasNext,
      'The dataset still contains one record'
    );

    Assert.areEqual(
      null,
      offsetResult.nextOffset,
      'OFFSET cannot continue because the next offset would be 2500'
    );

    // -------------------------------------------------------------------------
    // KEYSET traverses all records without OFFSET.
    // -------------------------------------------------------------------------

    DbQueryRequest keysetRequest = QueryTestSupport.deepPageRequest(
      DbPageRequest.KEYSET,
      pageSize
    );

    Set<Id> keysetIds = new Set<Id>();
    Integer keysetPages = 0;
    Integer keysetReturned = 0;

    while (true) {
      Assert.isTrue(keysetPages < 10, 'KEYSET pagination failed to terminate');

      DbQueryResult keysetResult = DbQueryService.execute(
        keysetRequest,
        pageSize
      );

      keysetReturned += keysetResult.records.size();
      for (SObject record : keysetResult.records) {
        Assert.isTrue(
          keysetIds.add(record.Id),
          'Each keyset row appears once across pages'
        );
      }

      keysetPages++;

      if (!keysetResult.hasNext) {
        Assert.areEqual(
          null,
          keysetResult.nextAfterId,
          'Final KEYSET page must not expose nextAfterId'
        );
        break;
      }

      Assert.areNotEqual(
        null,
        keysetResult.nextAfterId,
        'KEYSET must provide continuation while data remains'
      );

      keysetRequest.page.afterId = keysetResult.nextAfterId;
    }

    Assert.areEqual(
      2501,
      keysetReturned,
      'KEYSET returns exactly the matching population'
    );
    Assert.areEqual(
      2501,
      keysetIds.size(),
      'KEYSET must traverse all records beyond the OFFSET limit'
    );

    Assert.areEqual(
      6,
      keysetPages,
      '2501 records with page size 500 require six KEYSET pages'
    );

    // -------------------------------------------------------------------------
    // PAGE_CURSOR traverses all records using cursor positions.
    // -------------------------------------------------------------------------

    DbQueryRequest cursorRequest = QueryTestSupport.deepPageRequest(
      DbPageRequest.PAGE_CURSOR,
      pageSize
    );

    DbQueryResult cursorResult = DbQueryService.execute(
      cursorRequest,
      pageSize
    );

    Set<Id> cursorIds = new Set<Id>();
    Integer cursorPages = 0;

    while (true) {
      for (SObject record : cursorResult.records) {
        Assert.isTrue(
          cursorIds.add(record.Id),
          'PAGE_CURSOR must not return duplicate records'
        );
      }

      cursorPages++;

      if (!cursorResult.hasNext) {
        Assert.areEqual(
          null,
          cursorResult.nextPosition,
          'Final cursor page must not expose nextPosition'
        );
        break;
      }

      Assert.areNotEqual(
        null,
        cursorResult.nextPosition,
        'PAGE_CURSOR must provide a continuation position'
      );

      Assert.isTrue(
        cursorResult.nextPosition > 0,
        'Cursor continuation must move forward'
      );

      Assert.isTrue(
        cursorPages < 10,
        'PAGE_CURSOR pagination failed to terminate'
      );

      cursorResult = DbQueryService.fetchPage(
        cursorResult.cursor,
        cursorResult.nextPosition,
        pageSize,
        pageSize
      );
    }

    Assert.areEqual(
      2501,
      cursorIds.size(),
      'PAGE_CURSOR must traverse all records beyond the OFFSET limit'
    );

    Assert.areEqual(
      6,
      cursorPages,
      '2501 records with page size 500 require six cursor pages'
    );
    Test.stopTest();
  }
}
