public with sharing class ReturnPortalService {
  public static PortalReturnPage listRequests(Integer pageSize, String cursor) {
    Id accountId = requireCustomerAccount();
    Integer size = pageSize == null ||
      pageSize < 1
      ? ReturnPortalDomain.DEFAULT_PAGE_SIZE
      : Math.min(pageSize, ReturnPortalDomain.MAX_PAGE_SIZE);
    CursorPosition position;
    if (String.isNotBlank(cursor)) {
      try {
        if (cursor.length() > 512)
          throw new ReturnPortalDomain.PortalException('Invalid cursor');
        position = (CursorPosition) JSON.deserialize(
          EncodingUtil.base64Decode(cursor).toString(),
          CursorPosition.class
        );
        if (
          position == null ||
          position.createdAt == null ||
          position.recordId == null ||
          position.recordId.getSObjectType() != Return_Request__c.SObjectType
        ) {
          throw new ReturnPortalDomain.PortalException('Invalid cursor');
        }
      } catch (Exception e) {
        throw new ReturnPortalDomain.PortalException(
          'Trang không hợp lệ. Vui lòng tải lại danh sách.'
        );
      }
    }
    List<Return_Request__c> rows = ReturnRequestSelector.customerPage(
      accountId,
      size,
      position?.createdAt,
      position?.recordId
    );
    PortalReturnPage page = new PortalReturnPage();
    page.hasNext = rows.size() > size;
    if (page.hasNext)
      rows.remove(rows.size() - 1);
    for (Return_Request__c row : rows)
      page.requests.add(ReturnPortalDomain.project(row, true));
    if (page.hasNext) {
      Return_Request__c last = rows[rows.size() - 1];
      CursorPosition next = new CursorPosition();
      next.createdAt = last.CreatedDate;
      next.recordId = last.Id;
      page.nextCursor = EncodingUtil.base64Encode(
        Blob.valueOf(JSON.serialize(next))
      );
    }
    return page;
  }

  public static PortalReturn getRequest(String requestNumber) {
    Id accountId = requireCustomerAccount();
    String normalizedNumber = ReturnPortalDomain.normalizeNumber(requestNumber);
    List<Return_Request__c> rows = ReturnRequestSelector.customerRequest(
      accountId,
      normalizedNumber
    );
    if (rows.isEmpty())
      throw new ReturnPortalDomain.PortalException(
        'Không tìm thấy yêu cầu phù hợp.'
      );
    Return_Request__c request = rows[0];
    PortalReturn result = ReturnPortalDomain.project(request, true);
    if (request.Status__c == SmartReturnConstants.STATUS_REJECTED)
      result.rejectionReason = request.Rejection_Reason__c;
    ReturnPortalDomain.addDetails(
      result,
      ReturnRequestSelector.portalLines(request.Id),
      ReturnRequestSelector.portalHistory(request.Id)
    );
    return result;
  }

  private static Id requireCustomerAccount() {
    if (!FeatureManagement.checkPermission('SmartReturn_Portal_Customer')) {
      throw new ReturnPortalDomain.PortalException(
        'Vui lòng đăng nhập bằng tài khoản khách hàng để xem yêu cầu.'
      );
    }
    Id accountId = ReturnRequestSelector.currentCustomerAccount();
    if (accountId == null) {
      throw new ReturnPortalDomain.PortalException(
        'Tài khoản chưa liên kết với khách hàng. Vui lòng liên hệ bộ phận hỗ trợ.'
      );
    }
    return accountId;
  }

  private class CursorPosition {
    public Datetime createdAt;
    public Id recordId;
  }
}
