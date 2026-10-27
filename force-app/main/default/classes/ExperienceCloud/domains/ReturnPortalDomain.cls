public with sharing class ReturnPortalDomain {
  public static final Integer MAX_PAGE_SIZE = 50;
  public static final Integer DEFAULT_PAGE_SIZE = 10;
  public static String normalizeNumber(String requestNumber) {
    if (String.isBlank(requestNumber) || requestNumber.length() > 80) {
      throw new PortalException('Vui lòng nhập mã yêu cầu hợp lệ.');
    }
    return requestNumber.trim().toUpperCase();
  }

  public static Boolean matchesPhone(String phone, String suffix) {
    if (
      String.isBlank(phone) ||
      suffix == null ||
      !Pattern.matches('[0-9]{4}', suffix)
    )
      return false;
    String digits = phone.replaceAll('[^0-9]', '');
    return digits.length() >= 4 && digits.right(4) == suffix;
  }

  public static PortalReturn project(
    Return_Request__c request,
    Boolean includeAmount
  ) {
    PortalReturn result = new PortalReturn();
    result.requestNumber = request.Name;
    result.status = request.Status__c;
    result.createdAt = request.CreatedDate;
    if (includeAmount) {
      Boolean actual =
        request.Inspection_Completed_At__c != null ||
        new Set<String>{
            SmartReturnConstants.STATUS_REFUND_PROCESSING,
            SmartReturnConstants.STATUS_REFUND_FAILED,
            SmartReturnConstants.STATUS_COMPLETED
          }
          .contains(request.Status__c);
      result.refundAmount = actual
        ? request.Actual_Refund_Amount__c
        : request.Estimated_Refund_Amount__c;
      result.amountKind = actual ? 'ACTUAL' : 'ESTIMATED';
    }
    return result;
  }

  public static void addDetails(
    PortalReturn result,
    List<Return_Request_Line__c> lines,
    List<Return_Request__History> history
  ) {
    if (lines.size() > 1000 || history.size() > 1000) {
      throw new PortalException(
        'Yêu cầu có quá nhiều dữ liệu. Vui lòng liên hệ bộ phận hỗ trợ.'
      );
    }
    for (Return_Request_Line__c line : lines) {
      PortalReturnLine product = new PortalReturnLine();
      product.productName = line.Product__c == null
        ? 'Sản phẩm'
        : line.Product__r.Name;
      product.quantity = line.Requested_Quantity__c;
      result.lines.add(product);
    }
    PortalStatusChange created = new PortalStatusChange();
    created.status = 'CREATED';
    created.changedAt = result.createdAt;
    result.history.add(created);
    for (Return_Request__History change : history) {
      if (change.NewValue == null)
        continue;
      PortalStatusChange item = new PortalStatusChange();
      item.status = String.valueOf(change.NewValue);
      item.changedAt = change.CreatedDate;
      result.history.add(item);
    }
  }

  public class LookupPolicy {
    public Integer maxFailures;
    public Integer windowMinutes;
    public Integer lockMinutes;

    public LookupPolicy(
      Decimal maxFailures,
      Decimal windowMinutes,
      Decimal lockMinutes
    ) {
      if (
        maxFailures == null ||
        windowMinutes == null ||
        lockMinutes == null ||
        maxFailures < 1 ||
        maxFailures > 100 ||
        windowMinutes < 1 ||
        windowMinutes > 1440 ||
        lockMinutes < 1 ||
        lockMinutes > 1440 ||
        maxFailures != maxFailures.setScale(0) ||
        windowMinutes != windowMinutes.setScale(0) ||
        lockMinutes != lockMinutes.setScale(0)
      ) {
        throw new PortalException(
          'Cấu hình giới hạn tra cứu không hợp lệ. Vui lòng liên hệ quản trị viên.'
        );
      }
      this.maxFailures = maxFailures.intValue();
      this.windowMinutes = windowMinutes.intValue();
      this.lockMinutes = lockMinutes.intValue();
    }
  }

  public static void recordFailure(
    Portal_Lookup_Limit__c counter,
    LookupPolicy policy,
    Datetime nowTime
  ) {
    if (
      counter.Window_Started_At__c == null ||
      counter.Window_Started_At__c.addMinutes(policy.windowMinutes) <=
      nowTime ||
      (counter.Locked_Until__c != null &&
      counter.Locked_Until__c <= nowTime)
    ) {
      counter.Window_Started_At__c = nowTime;
      counter.Failure_Count__c = 0;
      counter.Locked_Until__c = null;
    }
    counter.Failure_Count__c =
      (counter.Failure_Count__c == null ? 0 : counter.Failure_Count__c) + 1;
    if (counter.Failure_Count__c >= policy.maxFailures) {
      counter.Locked_Until__c = nowTime.addMinutes(policy.lockMinutes);
    }
  }

  public class PortalException extends Exception {
  }
}
