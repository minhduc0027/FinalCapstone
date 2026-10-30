public inherited sharing class SmartReturnConfigService {
  private static SmartReturn_Settings__mdt settings;

  private static SmartReturn_Settings__mdt getSettings() {
    if (settings == null) {
      settings = SmartReturn_Settings__mdt.getInstance('Normal_Setting');
    }
    return settings;
  }

  public static Decimal getAutoApprovalLimit() {
    return getSettings().Auto_Approval_Limit__c;
  }

  public static Decimal getStoreApprovalLimit() {
    return getSettings().Store_Approval_Limit__c;
  }

  public static Integer getRiskRequestCount() {
    return Integer.valueOf(getSettings().Risk_Request_Count__c);
  }

  public static Integer getRiskWindowDays() {
    return Integer.valueOf(getSettings().Risk_Window_Days__c);
  }

  public static Decimal getRiskRefundAmount() {
    return getSettings().Risk_Refund_Amount__c;
  }

  public static Integer getApprovalTimeoutHours() {
    return Integer.valueOf(getSettings().Approval_Timeout_Hours__c);
  }

  public static Integer getGoodsReturnWindowDays() {
    return Integer.valueOf(getSettings().Goods_Reurn_Window_Days__c);
  }

  public static Integer getPayHubMaxTimeoutSecond() {
    return Integer.valueOf(getSettings().PayHub_Max_Timeout_Second__c);
  }

  public static Integer getPayHubMaxRetries() {
    return Integer.valueOf(getSettings().PayHub_Max_Retry__c);
  }

  public static Integer getPayHubRetryIntervalSeconds() {
    return Integer.valueOf(getSettings().PayHub_Retry_Interval__c);
  }

  // REFUND INTEGRATION: the dispatcher interval is independent of the retry delay.
  public static Integer getRefundScanIntervalMinutes() {
    Decimal configured = getSettings().Refund_Scan_Interval_Minutes__c;
    return configured == null ? 5 : Integer.valueOf(configured);
  }

  public static Decimal getRefundRounding() {
    return getSettings().Refund_Rounding__c;
  }

  //========================================================================
  // Feature flags
  //========================================================================
  public static Boolean isFeatureEnabled(String featureName) {
    SmartReturn_Feature__mdt config = SmartReturn_Feature__mdt.getInstance(
      featureName
    );

    return config != null && config.Enable__c;
  }

  //========================================================================
  // Refund rates
  //========================================================================
  public static Decimal getRefundRate(String conditionCode, String reasonCode) {
    List<Return_Refund_Rate__mdt> configs = [
      SELECT Refund_Rate__c
      FROM Return_Refund_Rate__mdt
      WHERE
        Condition_Code__c = :conditionCode
        AND Reason_Code__c = :reasonCode
        AND Is_Active__c = TRUE
      LIMIT 1
    ];

    return configs.isEmpty() ? 0 : configs[0].Refund_Rate__c;
  }

  //========================================================================
  // Refund category policy
  //========================================================================
  public static Return_Category_Policy__mdt getReturnCategoryPolicy(
    String productFamily
  ) {
    List<Return_Category_Policy__mdt> configs = [
      SELECT
        DeveloperName,
        Product_Family__c,
        Return_Allowed__c,
        Return_Window_Days__c,
        Is_Active__c
      FROM Return_Category_Policy__mdt
      WHERE Product_Family__c = :productFamily AND Is_Active__c = TRUE
      LIMIT 1
    ];

    return configs.isEmpty() ? null : configs[0];
  }
}
