/** Integration tests for common scalar and relationship keyset boundaries. */
@IsTest
private class DbKeysetFieldTest {
  @TestSetup
  static void setup() {
    QueryTestDataFactory.createKeysetRecords();
  }

  @IsTest
  static void textWithDuplicateValues() {
    verifyBoth('Account', 'Name');
  }
  @IsTest
  static void nullableIntegers() {
    verifyBoth('Account', 'NumberOfEmployees');
  }
  @IsTest
  static void nullableCurrency() {
    verifyBoth('Account', 'AnnualRevenue');
  }
  @IsTest
  static void nullablePhone() {
    verifyBoth('Account', 'Phone');
  }
  @IsTest
  static void nullableDates() {
    verifyBoth('Contact', 'Birthdate');
  }
  @IsTest
  static void dateTimeJsonContinuation() {
    verifyBoth('Task', 'ReminderDateTime');
  }
  @IsTest
  static void nullableEmail() {
    verifyBoth('Contact', 'Email');
  }
  @IsTest
  static void booleanGroups() {
    verifyBoth('Task', 'IsReminderSet');
  }
  @IsTest
  static void nullableReferences() {
    verifyBoth('Contact', 'AccountId');
  }
  @IsTest
  static void nullableParentFields() {
    verifyBoth('Contact', 'Account.Name');
  }

  @IsTest
  static void integerListFiltersKeepTypedBinds() {
    DbQueryRequest request = new DbQueryRequest();
    request.objectName = 'Account';
    request.fields = new List<String>{ 'Id' };
    request.orderBy = 'NumberOfEmployees';
    request.pageSize = 100;
    request.page = new DbPageRequest();
    request.page.strategy = DbPageRequest.KEYSET;
    request.filters = new List<FilterCondition>{
      new FilterCondition('NumberOfEmployees', 'IN', new List<Object>{ 1, 2 })
    };
    List<Account> expected = [
      SELECT Id
      FROM Account
      WHERE NumberOfEmployees IN (1, 2)
      ORDER BY NumberOfEmployees, Id
    ];
    Test.startTest();
    DbQueryResult result = DbQueryService.execute(request, 100);
    Test.stopTest();
    List<Id> actualIds = new List<Id>();
    for (SObject row : result.records) {
      actualIds.add(row.Id);
    }
    Assert.areEqual(
      QueryTestSupport.accountIds(expected),
      actualIds,
      'Integer IN filters must use integer binds'
    );
    Assert.isFalse(result.hasNext, 'Entire matching fixture fits in the page');
  }

  private static void verifyBoth(String objectName, String field) {
    Test.startTest();
    verifyTraversal(objectName, field, false);
    verifyTraversal(objectName, field, true);
    Test.stopTest();
  }

  private static void verifyTraversal(
    String objectName,
    String field,
    Boolean descending
  ) {
    String direction = descending ? ' DESC' : ' ASC';
    List<SObject> expected = Database.query(
      'SELECT Id FROM ' +
        objectName +
        ' ORDER BY ' +
        field +
        direction +
        ', Id' +
        direction
    );
    DbQueryRequest request = new DbQueryRequest();
    request.objectName = objectName;
    request.fields = new List<String>{ 'Id' }; // Compiler must project the sort value.
    request.orderBy = field.toLowerCase();
    request.orderDesc = descending;
    request.pageSize = 23; // Split both duplicate and null groups across pages.
    request.page = new DbPageRequest();
    request.page.strategy = ' keyset ';
    List<Id> actual = new List<Id>();
    Set<Id> uniqueIds = new Set<Id>();
    Integer pages = 0;
    while (true) {
      Assert.isTrue(pages++ < 20, 'Keyset must terminate: ' + field);
      DbQueryResult result = DbQueryService.execute(request, 23);
      for (SObject row : result.records) {
        Assert.isTrue(uniqueIds.add(row.Id), 'Duplicate record for ' + field);
        actual.add(row.Id);
      }
      if (!result.hasNext) {
        Assert.isNull(result.nextAfterId, 'Final page has no continuation');
        Assert.isNull(result.nextAfterValue, 'Final page has no sort boundary');
        break;
      }
      Assert.areEqual(
        result.records[result.records.size() - 1].Id,
        result.nextAfterId,
        'Continuation Id must be the last emitted record'
      );
      request.page.afterId = result.nextAfterId;
      // Exercise the scalar type conversion expected from web clients.
      request.page.afterValue = JSON.deserializeUntyped(
        JSON.serialize(result.nextAfterValue)
      );
    }
    List<Id> expectedIds = new List<Id>();
    for (SObject row : expected) {
      expectedIds.add(row.Id);
    }
    Assert.areEqual(
      251,
      actual.size(),
      'Entire bulk population must be visited'
    );
    Assert.areEqual(
      expectedIds,
      actual,
      'Exact platform ordering for ' + field + direction
    );
  }
}
