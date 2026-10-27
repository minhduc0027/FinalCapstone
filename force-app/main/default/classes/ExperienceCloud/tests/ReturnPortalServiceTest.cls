@IsTest
private class ReturnPortalServiceTest {
  @TestSetup
  static void setupData() {
    PortalTestDataFactory.setupData();
  }

  @IsTest
  static void externalCustomerSeesOnlyOwnAccountWithPagination() {
    User customer = [SELECT Id FROM User WHERE LastName = 'Portal A' LIMIT 1];
    Test.startTest();
    System.runAs(customer) {
      Assert.areEqual(
        3,
        [SELECT COUNT() FROM Return_Request__c],
        'SharingSet must restrict native record access, not only the Portal UI.'
      );
      PortalReturnPage first = ReturnPortalService.listRequests(2, null);
      Assert.areEqual(
        2,
        first.requests.size(),
        'Respect the requested page size.'
      );
      Assert.isTrue(
        first.hasNext,
        'The remaining own request must be pageable.'
      );
      PortalReturnPage second = ReturnPortalService.listRequests(
        2,
        first.nextCursor
      );
      Assert.areEqual(
        1,
        second.requests.size(),
        'Do not include the other Account\'s request.'
      );
      Assert.isFalse(second.hasNext, 'There is no third page.');
      Set<String> seen = new Set<String>();
      for (PortalReturn row : first.requests)
        seen.add(row.requestNumber);
      Assert.isFalse(
        seen.contains(second.requests[0].requestNumber),
        'Keyset paging must not repeat records with equal timestamps.'
      );
      Assert.isFalse(
        Return_Request__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
          )
          .isUpdateable(),
        'Customers must not edit return records.'
      );
      Assert.isFalse(
        Return_Request__c.Internal_Notes__c.getDescribe().isAccessible(),
        'Internal notes must not be accessible through native APIs.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void anotherCustomersNumberReturnsNoDetail() {
    User customer = [SELECT Id FROM User WHERE LastName = 'Portal A' LIMIT 1];
    String foreignNumber = [
      SELECT Name
      FROM Return_Request__c
      WHERE
        Customer__r.Name = 'Portal Customer B'
        AND Status__c = :SmartReturnConstants.STATUS_REJECTED
      LIMIT 1
    ]
    .Name;
    Test.startTest();
    System.runAs(customer) {
      try {
        ReturnPortalService.getRequest(foreignNumber);
        Assert.fail(
          'A known foreign request number must not authorize access.'
        );
      } catch (ReturnPortalDomain.PortalException e) {
        Assert.areEqual(
          'Không tìm thấy yêu cầu phù hợp.',
          e.getMessage(),
          'Treat foreign and unknown numbers identically.'
        );
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void ownDetailUsesExplicitEstimateAndSafeHistory() {
    User customer = [SELECT Id FROM User WHERE LastName = 'Portal A' LIMIT 1];
    String normalizedNumber = [
      SELECT Name
      FROM Return_Request__c
      WHERE Customer__r.Name = 'Portal Customer A'
      LIMIT 1
    ]
    .Name;
    Test.startTest();
    System.runAs(customer) {
      PortalReturn detail = ReturnPortalService.getRequest(normalizedNumber);
      Assert.areEqual(
        2490000,
        detail.refundAmount,
        'Use the request estimate before inspection.'
      );
      Assert.areEqual(
        'ESTIMATED',
        detail.amountKind,
        'Do not imply the amount has already been paid.'
      );
      Assert.areEqual(
        1,
        detail.lines.size(),
        'Include the authorized request\'s products.'
      );
      Assert.areEqual(
        'CREATED',
        detail.history[0].status,
        'Creation must not fabricate an approval history event.'
      );
      Assert.isFalse(
        JSON.serialize(detail).contains('PRIVATE STAFF NOTE'),
        'Internal notes must not enter the DTO.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void ownRejectedRequestIncludesReadOnlyReason() {
    User customer = [SELECT Id FROM User WHERE LastName = 'Portal A' LIMIT 1];
    Return_Request__c request = [
      SELECT Name, Rejection_Reason__c
      FROM Return_Request__c
      WHERE
        Customer__r.Name = 'Portal Customer A'
        AND Status__c = :SmartReturnConstants.STATUS_REJECTED
      LIMIT 1
    ];
    Test.startTest();
    System.runAs(customer) {
      PortalReturn detail = ReturnPortalService.getRequest(request.Name);
      Assert.areEqual(
        request.Rejection_Reason__c,
        detail.rejectionReason,
        'Customers must understand why their request was rejected.'
      );
      Assert.isTrue(
        Return_Request__c.Rejection_Reason__c.getDescribe().isAccessible(),
        'The customer permission set must grant reason read access.'
      );
      Assert.isFalse(
        Return_Request__c.Rejection_Reason__c.getDescribe().isUpdateable(),
        'Customers must not edit the rejection reason.'
      );
      Assert.isFalse(
        JSON.serialize(detail).contains('PRIVATE STAFF NOTE'),
        'Publishing a reason must not publish internal notes.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void nonRejectedRequestDoesNotExposeStaleReason() {
    User customer = [SELECT Id FROM User WHERE LastName = 'Portal A' LIMIT 1];
    Return_Request__c request = [
      SELECT Id, Name
      FROM Return_Request__c
      WHERE
        Customer__r.Name = 'Portal Customer A'
        AND Status__c = :SmartReturnConstants.STATUS_NEW
      LIMIT 1
    ];
    request.Rejection_Reason__c = 'Stale reason';
    update as system request;
    Test.startTest();
    System.runAs(customer) {
      Assert.isNull(
        ReturnPortalService.getRequest(request.Name).rejectionReason,
        'A stale reason must not appear before the request is rejected.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void malformedCursorIsRejected() {
    User customer = [SELECT Id FROM User WHERE LastName = 'Portal A' LIMIT 1];
    Test.startTest();
    System.runAs(customer) {
      try {
        ReturnPortalService.listRequests(10, 'not-a-cursor');
        Assert.fail('Malformed cursors must not reach the selector.');
      } catch (ReturnPortalDomain.PortalException e) {
        Assert.isTrue(
          e.getMessage().contains('Trang'),
          'Return a recoverable paging error.'
        );
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void internalUserCannotFallbackToAllCustomers() {
    Test.startTest();
    try {
      ReturnPortalService.listRequests(10, null);
      Assert.fail(
        'Internal or guest callers must not get a fallback full list.'
      );
    } catch (ReturnPortalDomain.PortalException e) {
      Assert.isTrue(
        e.getMessage().contains('đăng nhập'),
        'Explain the required customer context.'
      );
    }
    Test.stopTest();
  }
}
