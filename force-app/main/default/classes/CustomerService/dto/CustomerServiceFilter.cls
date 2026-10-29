public with sharing class CustomerServiceFilter {
  @AuraEnabled
  public String searchTerm { get; set; }

  @AuraEnabled
  public Integer pageSize { get; set; }

  @AuraEnabled
  public DbPageRequest page { get; set; }
}
