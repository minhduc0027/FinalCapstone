public class PortalReturnPage {
  @AuraEnabled
  public List<PortalReturn> requests = new List<PortalReturn>();
  @AuraEnabled
  public Boolean hasNext = false;
  @AuraEnabled
  public String nextCursor;
}
