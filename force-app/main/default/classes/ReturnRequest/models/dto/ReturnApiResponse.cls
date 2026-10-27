public class ReturnApiResponse {
  public class CreateResponse {
    public String requestNumber { get; set; }
    public String status { get; set; }
    public String approvalLevel { get; set; }
    public Decimal estimatedRefundAmount { get; set; }
    public List<CreateLineResponse> lines { get; set; }

    public CreateResponse() {
      lines = new List<CreateLineResponse>();
    }
  }

  public class CreateLineResponse {
    public String sku { get; set; }
    public Decimal quantity { get; set; }
    public Decimal unitPrice { get; set; }
    public Decimal refundRate { get; set; }
    public Decimal refundAmount { get; set; }
  }

  public class LookupResponse {
    public String requestNumber { get; set; }
    public String status { get; set; }
    public String orderNumber { get; set; }
    public Decimal refundAmount { get; set; }
    public List<LookupLineResponse> lines { get; set; }
    public List<HistoryResponse> history { get; set; }

    public LookupResponse() {
      lines = new List<LookupLineResponse>();
      history = new List<HistoryResponse>();
    }
  }

  public class LookupLineResponse {
    public String sku { get; set; }
    public Decimal quantity { get; set; }
    public String inspectionResult { get; set; }
    public Decimal refundAmount { get; set; }
  }

  public class HistoryResponse {
    public String status { get; set; }
    public Datetime changedAt { get; set; }

    public HistoryResponse(String status, Datetime changedAt) {
      this.status = status;
      this.changedAt = changedAt;
    }
  }

  public class ErrorResponse {
    public String errorCode { get; set; }
    public String message { get; set; }
    public String traceId { get; set; }
    public List<ErrorDetail> details { get; set; }

    public ErrorResponse() {
      details = new List<ErrorDetail>();
    }
  }

  public class ErrorDetail {
    public String sku { get; set; }
    public String code { get; set; }
    public String message { get; set; }
  }
}
