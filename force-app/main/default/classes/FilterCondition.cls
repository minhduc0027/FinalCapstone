public class FilterCondition {
    @AuraEnabled
    public String field;

    @AuraEnabled
    public String operator;

    @AuraEnabled
    public Object value;

    public FilterCondition() {
    }

    public FilterCondition(
        String field,
        String operator,
        Object value
    ) {
        this.field = field;
        this.operator = operator;
        this.value = value;
    }
}