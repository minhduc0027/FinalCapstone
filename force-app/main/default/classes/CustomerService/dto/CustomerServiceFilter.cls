public with sharing class CustomerServiceFilter {
  @AuraEnabled
  public String customerPhone { get; set; }

  @AuraEnabled
  public String orderNumber { get; set; }

  @AuraEnabled
  public String customerName { get; set; }

  @AuraEnabled
  public Integer pageSize { get; set; }

  @AuraEnabled
  public DbPageRequest page { get; set; }
}
