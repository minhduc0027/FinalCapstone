public with sharing class CustomerServicePageResult {
  @AuraEnabled
  public List<CustomerServiceRequestRow> records { get; set; }

  @AuraEnabled
  public Boolean hasNext { get; set; }

  @AuraEnabled
  public String soql { get; set; }

  @AuraEnabled
  public Integer bindCount { get; set; }

  public CustomerServicePageResult() {
    records = new List<CustomerServiceRequestRow>();
    hasNext = false;
  }
}
