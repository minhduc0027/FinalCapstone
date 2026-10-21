public with sharing class DbQueryRequest {
  @AuraEnabled
  public String objectName { get; set; }
  @AuraEnabled
  public List<String> fields { get; set; }
  @AuraEnabled
  public List<FilterCondition> filters { get; set; }
  @AuraEnabled
  public String orderBy { get; set; }
  @AuraEnabled
  public Boolean orderDesc { get; set; }
  @AuraEnabled
  public Integer pageSize { get; set; }
  @AuraEnabled
  public DbPageRequest page { get; set; }
}
