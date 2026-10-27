public with sharing class InspectionPageResult {
  @AuraEnabled
  public List<InspectionRow> records { get; set; }

  @AuraEnabled
  public Boolean hasNext { get; set; }

  @AuraEnabled
  public Integer bindCount { get; set; }

  public InspectionPageResult() {
    records = new List<InspectionRow>();
    hasNext = false;
    bindCount = 0;
  }
}
