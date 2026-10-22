public with sharing class DbQueryResult {
  @AuraEnabled
  public List<SObject> records { get; set; }
  @AuraEnabled
  public Boolean hasNext { get; set; }
  @AuraEnabled
  public String strategy { get; set; }
  @AuraEnabled
  public Integer nextOffset { get; set; }
  @AuraEnabled
  public Id nextAfterId { get; set; }
  /** Last sort value for KEYSET continuation; use together with nextAfterId. */
  @AuraEnabled
  public Object nextAfterValue { get; set; }
  @AuraEnabled
  public Integer nextPosition { get; set; }
  @AuraEnabled
  public Database.PaginationCursor cursor { get; set; }
  @AuraEnabled
  public Integer totalRecords { get; set; }
  public String soql { get; set; }
  public Integer bindCount { get; set; }
  public DbQueryResult() {
    records = new List<SObject>();
    hasNext = false;
    bindCount = 0;
  }
}
