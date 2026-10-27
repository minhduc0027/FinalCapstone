/**
 * Proof-based guest lookup without granting guests direct access to private records.
 * Privileged access is restricted by a custom permission and explicit response allowlist.
 */
public without sharing class PortalGuestService {
  public static Map<String, Object> lookup(
    String requestNumber,
    String phoneSuffix,
    String sourceAddress
  ) {
    if (!FeatureManagement.checkPermission('SmartReturn_Portal_Guest_Lookup')) {
      throw new ReturnPortalDomain.PortalException('Không có quyền tra cứu.');
    }
    if (String.isBlank(sourceAddress)) {
      throw new ReturnPortalDomain.PortalException(
        'Không thể xác minh nguồn truy cập. Vui lòng thử lại sau.'
      );
    }
    String normalizedNumber = ReturnPortalDomain.normalizeNumber(requestNumber);
    if (phoneSuffix == null || !Pattern.matches('[0-9]{4}', phoneSuffix)) {
      return new Map<String, Object>{ 'outcome' => 'NOT_FOUND' };
    }
    SmartReturn_Settings__mdt settings = SmartReturn_Settings__mdt.getInstance(
      'Normal_Setting'
    );
    if (settings == null)
      throw new ReturnPortalDomain.PortalException('Thiếu cấu hình tra cứu.');
    ReturnPortalDomain.LookupPolicy policy = new ReturnPortalDomain.LookupPolicy(
      settings.Portal_Max_Failures__c,
      settings.Portal_Window_Minutes__c,
      settings.Portal_Lock_Minutes__c
    );
    // Store only the hash. The attempted phone suffix never changes the counter identity.
    String fingerprint = EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(
          UserInfo.getOrganizationId() +
            '|' +
            sourceAddress +
            '|' +
            normalizedNumber
        )
      )
    );
    Portal_Lookup_Limit__c counter;
    List<Portal_Lookup_Limit__c> counters = PortalGuestSelector.counter(
      fingerprint
    );
    if (counters.isEmpty()) {
      counter = new Portal_Lookup_Limit__c(
        Fingerprint__c = fingerprint,
        Failure_Count__c = 0
      );
      Database.SaveResult created = Database.insert(
        counter,
        false,
        AccessLevel.SYSTEM_MODE
      );
      if (!created.isSuccess()) {
        if (
          created.getErrors()[0].getStatusCode() != StatusCode.DUPLICATE_VALUE
        ) {
          throw new ReturnPortalDomain.PortalException(
            'Không thể kiểm tra giới hạn tra cứu.'
          );
        }
        // Another transaction created this exact pair; lock its persisted counter.
        counters = PortalGuestSelector.counter(fingerprint);
        if (counters.isEmpty())
          throw new ReturnPortalDomain.PortalException('Vui lòng thử lại.');
        counter = counters[0];
      }
    } else {
      counter = counters[0];
    }
    Datetime nowTime = System.now();
    if (counter.Locked_Until__c != null && counter.Locked_Until__c > nowTime) {
      Long remainingMs = counter.Locked_Until__c.getTime() - nowTime.getTime();
      Integer remainingMinutes = (Integer) ((remainingMs + 59999) / 60000);
      return new Map<String, Object>{
        'outcome' => 'LOCKED',
        'retryAfterMinutes' => remainingMinutes
      };
    }

    List<Return_Request__c> rows = PortalGuestSelector.requestByNumber(
      normalizedNumber
    );
    if (
      rows.isEmpty() ||
      !ReturnPortalDomain.matchesPhone(rows[0].Customer__r.Phone, phoneSuffix)
    ) {
      ReturnPortalDomain.recordFailure(counter, policy, nowTime);
      update as system counter;
      Map<String, Object> failure = new Map<String, Object>{
        'outcome' => counter.Locked_Until__c == null ? 'NOT_FOUND' : 'LOCKED'
      };
      if (counter.Locked_Until__c != null)
        failure.put('retryAfterMinutes', policy.lockMinutes);
      return failure;
    }

    counter.Failure_Count__c = 0;
    counter.Window_Started_At__c = nowTime;
    counter.Locked_Until__c = null;
    update as system counter;
    Return_Request__c request = rows[0];
    PortalReturn result = ReturnPortalDomain.project(request, false);
    if (request.Status__c == SmartReturnConstants.STATUS_REJECTED)
      result.rejectionReason = request.Rejection_Reason__c;
    ReturnPortalDomain.addDetails(
      result,
      PortalGuestSelector.lines(request.Id),
      PortalGuestSelector.history(request.Id)
    );
    return new Map<String, Object>{ 'outcome' => 'FOUND', 'request' => result };
  }
}
