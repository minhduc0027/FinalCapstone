public with sharing class ApprovalPageResult {
  @AuraEnabled
  public List<ApprovalRow> records { get; set; }

  @AuraEnabled
  public Boolean hasNext { get; set; }

  @AuraEnabled
  public String soql { get; set; }

  @AuraEnabled
  public Integer bindCount { get; set; }

  public ApprovalPageResult() {
    records = new List<ApprovalRow>();
    hasNext = false;
  }
}
