@IsTest
private class DbKeysetStrategyTest {
  private static final Integer TOTAL_ACCOUNTS = 5;
  private static final Integer DEFAULT_PAGE_SIZE = 2;
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createPageAccounts();
  }
  @IsTest
  static void keysetVisitsEachRecordInBothDirections() {
    Test.startTest();
    for (Boolean descending : new List<Boolean>{ false, true }) {
      List<Account> expectedAccounts = descending
        ? [
            SELECT Id
            FROM Account
            WHERE Name LIKE 'Page %'
            ORDER BY Id DESC
          ]
        : [
            SELECT Id
            FROM Account
            WHERE Name LIKE 'Page %'
            ORDER BY Id ASC
          ];

      List<Id> expectedIds = QueryTestSupport.accountIds(expectedAccounts);
      List<Id> actualIds = new List<Id>();
      Set<Id> uniqueIds = new Set<Id>();

      DbQueryRequest request = QueryTestSupport.newRequest(
        DbPageRequest.KEYSET
      );
      request.orderDesc = descending;

      Boolean more = true;
      Integer pages = 0;

      while (more) {
        Assert.isTrue(pages < 10, 'KEYSET pagination failed to terminate');

        DbQueryResult result = DbQueryService.execute(request, 2);

        pages++;

        Assert.areEqual(DbPageRequest.KEYSET, result.strategy);
        Assert.isTrue(
          result.records.size() <= 2,
          'Result must not exceed effective page size'
        );

        for (SObject record : result.records) {
          Id recordId = record.Id;

          Assert.isTrue(
            uniqueIds.add(recordId),
            'KEYSET must not return duplicate records'
          );

          actualIds.add(recordId);
        }

        if (result.hasNext) {
          Assert.areNotEqual(
            null,
            result.nextAfterId,
            'hasNext=true requires nextAfterId'
          );
          Assert.isTrue(
            !result.records.isEmpty(),
            'A continuing page must contain records'
          );
          Assert.areEqual(
            result.records[result.records.size() - 1].Id,
            result.nextAfterId,
            'nextAfterId must equal the last returned record Id'
          );
        } else {
          Assert.areEqual(
            null,
            result.nextAfterId,
            'Final KEYSET page must not expose nextAfterId'
          );
        }

        more = result.hasNext;
        request.page.afterId = result.nextAfterId;
      }

      Assert.areEqual(TOTAL_ACCOUNTS, uniqueIds.size());
      Assert.areEqual(3, pages);
      Assert.areEqual(expectedIds, actualIds);
      Assert.areEqual(false, more);
    }
    Test.stopTest();
  }
  @IsTest
  static void keysetWorksWithoutExplicitIdProjection() {
    Test.startTest();
    DbQueryRequest request = QueryTestSupport.newRequest(DbPageRequest.KEYSET);

    // Id isn't explicitly selected. Salesforce still makes the record Id
    // available on queried SObjects.
    request.fields = new List<String>{ 'Name' };

    DbQueryResult result = DbQueryService.execute(request, 2);

    Assert.areEqual(2, result.records.size());
    Assert.areEqual(true, result.hasNext);
    Assert.areNotEqual(null, result.nextAfterId);
    Assert.areEqual(
      result.records[result.records.size() - 1].Id,
      result.nextAfterId
    );
    Test.stopTest();
  }
}
