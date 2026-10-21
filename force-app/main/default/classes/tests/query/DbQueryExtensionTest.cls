@IsTest
private class DbQueryExtensionTest {
  private class CustomFactory extends DbPageStrategyFactory {
    public override IDbPageStrategy resolve(String strategy) {
      return strategy == 'CUSTOM'
        ? new CustomStrategy()
        : super.resolve(strategy);
    }
  }
  private class CustomStrategy implements IDbPageStrategy {
    public DbQueryResult execute(
      DbQueryPlan plan,
      DbPageRequest page,
      Integer pageSize
    ) {
      Assert.areEqual(
        2,
        pageSize,
        'Custom strategies receive the server-capped size'
      );
      Assert.isTrue(
        plan.toSoql().contains('FROM Account'),
        'Custom strategies receive a validated query'
      );
      DbQueryResult result = new DbQueryResult();
      result.strategy = 'CUSTOM';
      return result;
    }
  }
  @IsTest
  static void supportsCallerOwnedStrategies() {
    DbQueryRequest request = new DbQueryRequest();
    request.objectName = 'Account';
    request.fields = new List<String>{ 'Id' };
    request.pageSize = 10;
    request.page = new DbPageRequest();
    request.page.strategy = 'CUSTOM';
    Test.startTest();
    DbQueryResult result = DbQueryService.execute(
      request,
      2,
      new CustomFactory()
    );
    Test.stopTest();
    Assert.areEqual(
      'CUSTOM',
      result.strategy,
      'Additional strategies do not require changing the service'
    );
  }
}
