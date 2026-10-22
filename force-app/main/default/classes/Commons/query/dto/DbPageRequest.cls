public with sharing class DbPageRequest {
  public static final String OFFSET = 'OFFSET';
  public static final String KEYSET = 'KEYSET';
  public static final String PAGE_CURSOR = 'PAGE_CURSOR';

  @AuraEnabled
  public String strategy { get; set; }
  @AuraEnabled
  public Integer offsetSize { get; set; }
  @AuraEnabled
  public Id afterId { get; set; }
  /** Last sort value paired with afterId; null represents a null field value. */
  @AuraEnabled
  public Object afterValue { get; set; }
}
