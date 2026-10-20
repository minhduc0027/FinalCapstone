public class ReportResult {
    @AuraEnabled
    public List<SObject> records;

    @AuraEnabled
    public String soql;

    @AuraEnabled
    public Integer bindCount;

    @AuraEnabled
    public Boolean truncated;

    public ReportResult() {
        records = new List<SObject>();
        bindCount = 0;
        truncated = false;
    }
}