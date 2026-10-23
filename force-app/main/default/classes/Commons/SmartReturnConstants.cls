public with sharing class SmartReturnConstants {
  private SmartReturnConstants() {
  }
  //========================================================
  // Return Request Statuses
  //========================================================
  public static final String STATUS_NEW = 'NEW';
  public static final String STATUS_PENDING_APPROVAL = 'PENDING_APPROVAL';
  public static final String STATUS_AWAITING_GOODS = 'AWAITING_GOODS';
  public static final String STATUS_INSPECTING = 'INSPECTING';
  public static final String STATUS_REFUND_PROCESSING = 'REFUND_PROCESSING';
  public static final String STATUS_COMPLETED = 'COMPLETED';
  public static final String STATUS_REFUND_FAILED = 'REFUND_FAILED';
  public static final String STATUS_REJECTED = 'REJECTED';
  public static final String STATUS_CANCELLED = 'CANCELLED';
  public static final String STATUS_RE_CONFIRMING = 'RE_CONFIRMING';

  //========================================================
  // Approval Levels
  //========================================================
  public static final String APPROVAL_AUTO = 'AUTO';
  public static final String APPROVAL_CHT = 'CHT';
  public static final String APPROVAL_QLV = 'QLV';

  //========================================================
  // Eligible Reason Codes
  //========================================================
  public static final String REASON_CODE_CUSTOMER_DAMAGED = 'CUSTOMER_DAMAGED';
  public static final String REASON_CODE_DEFECT = 'DEFECT';
  public static final String REASON_CODE_NOT_SATISFIED = 'NOT_SATISFIED';
  public static final String REASON_CODE_WRONG_ITEM = 'WRONG_ITEM';

  //========================================================
  // Goods Condition Codes
  //========================================================
  public static final String GOODS_CONDITION_USED = 'USED';
  public static final String GOODS_CONDITION_SEALED = 'SEALED';
  public static final String GOODS_CONDITION_OPENED = 'OPENED';

  //========================================================
  // Source Channels
  //========================================================
  public static final String SOURCE_APP = 'APP';
  public static final String SOURCE_POS = 'POS';
  public static final String SOURCE_MIGRATION = 'MIGRATION';
  public static final String SOURCE_STORE = 'STORE';
}
