@IsTest
private class SmartReturnConfigServiceTests {
  @IsTest
  static void testSettingsMethods() {
    Test.startTest();

    Decimal autoApproval = SmartReturnConfigService.getAutoApprovalLimit();

    Decimal storeApproval = SmartReturnConfigService.getStoreApprovalLimit();

    Integer riskCount = SmartReturnConfigService.getRiskRequestCount();

    Integer riskWindow = SmartReturnConfigService.getRiskWindowDays();

    Decimal riskRefund = SmartReturnConfigService.getRiskRefundAmount();

    Integer timeoutHours = SmartReturnConfigService.getApprovalTimeoutHours();

    Integer returnWindow = SmartReturnConfigService.getGoodsReturnWindowDays();

    Integer payhubTimeout = SmartReturnConfigService.getPayHubMaxTimeoutSecond();

    Integer payhubRetry = SmartReturnConfigService.getPayHubMaxRetries();

    Integer retryInterval = SmartReturnConfigService.getPayHubRetryInterval();

    Decimal refundRounding = SmartReturnConfigService.getRefundRounding();

    Test.stopTest();

    System.assertNotEquals(null, autoApproval);
    System.assertNotEquals(null, storeApproval);
    System.assertNotEquals(null, riskCount);
    System.assertNotEquals(null, riskWindow);
    System.assertNotEquals(null, riskRefund);
    System.assertNotEquals(null, timeoutHours);
    System.assertNotEquals(null, returnWindow);
    System.assertNotEquals(null, payhubTimeout);
    System.assertNotEquals(null, payhubRetry);
    System.assertNotEquals(null, retryInterval);
    System.assertNotEquals(null, refundRounding);
  }

  @IsTest
  static void testFeatureEnabled_WhenFeatureExists() {
    Test.startTest();

    Boolean result = SmartReturnConfigService.isFeatureEnabled('Auto_Approval');

    Test.stopTest();

    System.assertNotEquals(null, result);
  }

  @IsTest
  static void testFeatureEnabled_WhenFeatureNotExists() {
    Test.startTest();

    Boolean result = SmartReturnConfigService.isFeatureEnabled(
      'UNKNOWN_FEATURE'
    );

    Test.stopTest();

    System.assertEquals(false, result);
  }

  @IsTest
  static void testGetRefundRate_NotFound() {
    Test.startTest();

    Decimal rate = SmartReturnConfigService.getRefundRate(
      'NOT_EXIST',
      'NOT_EXIST'
    );

    Test.stopTest();

    System.assertEquals(0, rate);
  }

  @IsTest
  static void testGetRefundRate_Found() {
    Return_Refund_Rate__mdt config = [
      SELECT Condition_Code__c, Reason_Code__c, Refund_Rate__c
      FROM Return_Refund_Rate__mdt
      LIMIT 1
    ];

    Test.startTest();

    Decimal rate = SmartReturnConfigService.getRefundRate(
      config.Condition_Code__c,
      config.Reason_Code__c
    );

    Test.stopTest();

    System.assertEquals(config.Refund_Rate__c, rate);
  }

  @IsTest
  static void testGetReturnCategoryPolicy_Found() {
    Return_Category_Policy__mdt config = [
      SELECT
        DeveloperName,
        Product_Family__c,
        Return_Allowed__c,
        Return_Window_Days__c,
        Is_Active__c
      FROM Return_Category_Policy__mdt
      LIMIT 1
    ];

    Test.startTest();

    Return_Category_Policy__mdt policy = SmartReturnConfigService.getReturnCategoryPolicy(
      config.Product_Family__c
    );

    Test.stopTest();

    System.assertEquals(config, policy);
  }

  @IsTest
  static void testGetReturnCategoryPolicy_NotFound() {
    Test.startTest();
    Return_Category_Policy__mdt policy = SmartReturnConfigService.getReturnCategoryPolicy(
      'NOT_EXIST'
    );
    Test.stopTest();
    System.assertEquals(null, policy);
  }
}
