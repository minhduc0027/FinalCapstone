public with sharing class FilterCondition {
  @AuraEnabled
  public String field { get; set; }
  @AuraEnabled
  public String operator { get; set; }
  @AuraEnabled
  public Object value { get; set; }

  public FilterCondition() {
  }

  public FilterCondition(String field, String operator, Object value) {
    this.field = field;
    this.operator = operator;
    this.value = value;
  }
}
