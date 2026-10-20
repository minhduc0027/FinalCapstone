public class ReportRequest {
    @AuraEnabled
    public String objectName;

    @AuraEnabled
    public List<String> fields;

    @AuraEnabled
    public List<FilterCondition> filters;

    /*
     * Backward compatibility.
     */
    @AuraEnabled
    public String orderBy;

    /*
     * New multi-field ordering.
     */
    @AuraEnabled
    public List<String> orderByFields;

    @AuraEnabled
    public Boolean orderDesc;

    @AuraEnabled
    public Integer limitSize;

    @AuraEnabled
    public KeysetCursor keysetCursor;

    public ReportRequest() {
        fields = new List<String>();
        filters = new List<FilterCondition>();
        orderByFields = new List<String>();
        orderDesc = false;
    }
}