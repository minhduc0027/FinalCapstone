public with sharing class CustomerServiceController {
  @AuraEnabled(cacheable=true)
  public static CustomerServicePageResult getReturnRequests(
    CustomerServiceFilter filter
  ) {
    try {
      return CustomerService.getReturnRequestsForCustomerService(filter);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
