@IsTest
public with sharing class QueryTestSupport {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  public static DbQueryRequest newRequest(String strategy) {
    DbQueryRequest request = new DbQueryRequest();

    request.objectName = 'Account';
    request.fields = new List<String>{ 'Name' };
    request.filters = new List<FilterCondition>{
      new FilterCondition('Name', 'LIKE', 'Page %')
    };
    request.pageSize = DEFAULT_PAGE_SIZE;
    request.page = new DbPageRequest();
    request.page.strategy = strategy;

    return request;
  }
  public static Set<Id> idsOf(List<SObject> records) {
    Set<Id> ids = new Set<Id>();

    for (SObject record : records) {
      ids.add(record.Id);
    }

    return ids;
  }
  public static List<Id> accountIds(List<Account> accounts) {
    List<Id> ids = new List<Id>();

    for (Account account : accounts) {
      ids.add(account.Id);
    }

    return ids;
  }
  public static void assertNoOverlap(
    List<SObject> firstPage,
    List<SObject> secondPage
  ) {
    Set<Id> overlap = idsOf(firstPage);
    overlap.retainAll(idsOf(secondPage));

    Assert.areEqual(
      new Set<Id>(),
      overlap,
      'Pagination pages must not overlap'
    );
  }
  public static void assertCursorContinuation(
    DbQueryResult result,
    Integer currentPosition
  ) {
    Assert.areEqual(true, result.hasNext, 'Expected another cursor page');
    Assert.areNotEqual(
      null,
      result.cursor,
      'Cursor must be returned for continuation'
    );
    Assert.areNotEqual(
      null,
      result.nextPosition,
      'hasNext=true requires nextPosition'
    );
    Assert.isTrue(
      result.nextPosition > currentPosition,
      'nextPosition must move the cursor forward'
    );
    Assert.isTrue(
      result.nextPosition < result.totalRecords,
      'nextPosition must point inside the remaining result set'
    );
  }
  public static void assertInvalidRequest(
    DbQueryRequest request,
    String caseName
  ) {
    try {
      DbQueryService.execute(request, 10);

      Assert.isTrue(false, 'Expected DbQueryException for: ' + caseName);
    } catch (DbQueryException expected) {
      Assert.areNotEqual(null, expected.getMessage(), caseName);
    }
  }
  public static void assertCursorPositionRejected(
    Database.PaginationCursor cursor,
    Integer position,
    String expectedMessage
  ) {
    try {
      DbQueryService.fetchPage(cursor, position, 2, 2);

      Assert.isTrue(false, 'Expected invalid cursor position rejection');
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage()
          .toLowerCase()
          .contains(expectedMessage.toLowerCase()),
        expected.getMessage()
      );
    }
  }
  public static void assertCursorPageSizeRejected(
    Database.PaginationCursor cursor,
    Integer pageSize
  ) {
    try {
      DbQueryService.fetchPage(cursor, 0, pageSize, pageSize);

      Assert.isTrue(false, 'Expected invalid cursor page size rejection');
    } catch (DbQueryException expected) {
      Assert.isTrue(
        expected.getMessage().contains('2000'),
        expected.getMessage()
      );
    }
  }
  public static void insertDeepPageAccounts(Integer count) {
    List<Account> accounts = new List<Account>();

    for (Integer i = 0; i < count; i++) {
      accounts.add(
        new Account(Name = 'Deep Page ' + String.valueOf(i).leftPad(4, '0'))
      );
    }

    insert accounts;
  }
  public static DbQueryRequest deepPageRequest(
    String strategy,
    Integer pageSize
  ) {
    DbQueryRequest request = new DbQueryRequest();

    request.objectName = 'Account';
    request.fields = new List<String>{ 'Name' };
    request.filters = new List<FilterCondition>{
      new FilterCondition('Name', 'LIKE', 'Deep Page %')
    };
    request.orderBy = 'Id';
    request.orderDesc = false;
    request.pageSize = pageSize;

    request.page = new DbPageRequest();
    request.page.strategy = strategy;

    return request;
  }
}
