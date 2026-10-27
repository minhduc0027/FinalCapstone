public with sharing class InspectionFilter {
  @AuraEnabled
  public Id storeId { get; set; }

  @AuraEnabled
  public String sourceChannel { get; set; }

  @AuraEnabled
  public Date fromDate { get; set; }

  @AuraEnabled
  public Date toDate { get; set; }

  @AuraEnabled
  public String sortBy { get; set; }

  @AuraEnabled
  public Boolean sortDescending { get; set; }

  @AuraEnabled
  public Integer pageSize { get; set; }

  @AuraEnabled
  public DbPageRequest page { get; set; }
}
