public class CreateReturnOrderHeader {
  @AuraEnabled
  public Id orderId { get; set; }

  @AuraEnabled
  public String orderNumber { get; set; }

  @AuraEnabled
  public Id customerId { get; set; }

  @AuraEnabled
  public String customerName { get; set; }

  @AuraEnabled
  public String customerPhone { get; set; }

  @AuraEnabled
  public Date purchaseDate { get; set; }

  @AuraEnabled
  public Date deliveryDate { get; set; }

  @AuraEnabled
  public Id storeId { get; set; }

  @AuraEnabled
  public String storeName { get; set; }

  @AuraEnabled
  public String storeCode { get; set; }
}
