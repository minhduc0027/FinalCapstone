public class ReturnApiRequest {
  public String externalRequestId { get; set; }
  public String channel { get; set; }
  public String orderNumber { get; set; }
  public String customerPhone { get; set; }
  public String storeCode { get; set; }
  public List<ReturnApiLineRequest> lines { get; set; }

  public class ReturnApiLineRequest {
    public String sku { get; set; }
    public Decimal quantity { get; set; }
    public String reason { get; set; }
    public String condition { get; set; }
  }
}
