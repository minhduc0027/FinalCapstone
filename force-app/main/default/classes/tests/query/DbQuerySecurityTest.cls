/** Verifies user-mode queries reject objects without read permission. */
@IsTest
private class DbQuerySecurityTest {
  @IsTest
  static void rejectsObjectsWithoutReadAccess() {
    Profile restricted = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      ORDER BY Name
      LIMIT 1
    ];
    User reader = new User(
      Alias = 'qreader',
      Email = 'query-reader@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Query Reader',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Etc/UTC',
      Username = 'query-reader-' +
        UserInfo.getOrganizationId() +
        '-' +
        DateTime.now().getTime() +
        '@example.invalid',
      ProfileId = restricted.Id
    );
    insert reader;
    System.runAs(reader) {
      Assert.isFalse(
        Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
          .isAccessible(),
        'Restricted test profile must not have Account read access'
      );
      DbQueryRequest request = new DbQueryRequest();
      request.objectName = 'Account';
      request.fields = new List<String>{ 'Id', 'Name' };
      request.pageSize = 1;
      Test.startTest();
      try {
        DbQueryService.execute(request, 1);
        Assert.fail('Objects without CRUD read access must not be queried');
      } catch (DbQueryException expected) {
        Assert.isTrue(
          !String.isBlank(expected.getMessage()),
          'Access error must be explained'
        );
      }
      Test.stopTest();
    }
  }
}
