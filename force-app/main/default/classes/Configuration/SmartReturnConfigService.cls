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

  public static Integer getPayHubRetryInterval() {
    return Integer.valueOf(getSettings().PayHub_Retry_Interval__c);
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
}
