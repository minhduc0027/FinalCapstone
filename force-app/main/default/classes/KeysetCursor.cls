public class KeysetCursor {
    @AuraEnabled
    public String primaryField;

    @AuraEnabled
    public Object primaryValue;

    @AuraEnabled
    public Id recordId;

    @AuraEnabled
    public Boolean descending;

    public KeysetCursor() {
        descending = true;
    }

    public KeysetCursor(
        String primaryField,
        Object primaryValue,
        Id recordId,
        Boolean descending
    ) {
        this.primaryField = primaryField;
        this.primaryValue = primaryValue;
        this.recordId = recordId;
        this.descending = descending;
    }
}