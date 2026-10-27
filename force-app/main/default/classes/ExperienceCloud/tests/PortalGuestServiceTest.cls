@IsTest
private class PortalGuestServiceTest {
  @TestSetup
  static void setupData() {
    PortalTestDataFactory.setupData();
  }

  @IsTest
  static void correctProofReturnsOnlyGuestFields() {
    Return_Request__c request = [
      SELECT Id, Name
      FROM Return_Request__c
      WHERE
        Customer__r.Name = 'Portal Customer A'
        AND Status__c = :SmartReturnConstants.STATUS_REJECTED
      LIMIT 1
    ];
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    Map<String, Object> result;
    Test.startTest();
    System.runAs(visitor) {
      Assert.isFalse(
        Return_Request__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
          )
          .isAccessible(),
        'Guest entry permission must not grant direct record reads.'
      );
      result = PortalGuestService.lookup(
        request.Name.toLowerCase(),
        '4567',
        '203.0.113.1'
      );
    }
    Test.stopTest();
    Assert.areEqual(
      'FOUND',
      result.get('outcome'),
      'Correct code and phone suffix must match.'
    );
    PortalReturn detail = (PortalReturn) result.get('request');
    Assert.areEqual(
      'Nồi chiên không dầu',
      detail.lines[0].productName,
      'D.4 permits the product name.'
    );
    Assert.areEqual(2, detail.lines[0].quantity, 'D.4 permits the quantity.');
    Assert.areEqual(
      'Sản phẩm đã quá thời hạn đổi trả.',
      detail.rejectionReason,
      'Verified guests may read the customer-facing rejection reason.'
    );
    String payload = JSON.serialize(result, true);
    for (
      String forbidden : new List<String>{
        'refundAmount',
        'amountKind',
        'PRIVATE STAFF NOTE',
        '4567',
        'Phone',
        String.valueOf(request.Id)
      }
    ) {
      Assert.isFalse(
        payload.contains(forbidden),
        'Guest payload must exclude ' + forbidden
      );
    }
  }

  @IsTest
  static void nonRejectedLookupDoesNotExposeStaleReason() {
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
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    Test.startTest();
    System.runAs(visitor) {
      Map<String, Object> response = PortalGuestService.lookup(
        request.Name,
        '4567',
        '203.0.113.7'
      );
      Assert.areEqual(
        'FOUND',
        response.get('outcome'),
        'Valid proof must match.'
      );
      PortalReturn detail = (PortalReturn) response.get('request');
      Assert.isNull(
        detail.rejectionReason,
        'A non-rejected request must not expose a stale rejection reason.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void wrongCodeAndWrongSuffixAreIndistinguishable() {
    String normalizedNumber = [SELECT Name FROM Return_Request__c LIMIT 1].Name;
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    Test.startTest();
    System.runAs(visitor) {
      String wrongPhone = JSON.serialize(
        PortalGuestService.lookup(normalizedNumber, '0000', '203.0.113.2'),
        true
      );
      String wrongCode = JSON.serialize(
        PortalGuestService.lookup('RR-DOES-NOT-EXIST', '0000', '203.0.113.2'),
        true
      );
      Assert.areEqual(
        wrongCode,
        wrongPhone,
        'Neither response may reveal whether the code exists.'
      );
      Assert.isFalse(
        wrongPhone.contains('rejectionReason'),
        'Incorrect proof must not expose the rejection reason.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void lockSurvivesChangingGuessesAndOnlyBlocksThePair() {
    String normalizedNumber = [
      SELECT Name
      FROM Return_Request__c
      WHERE Customer__r.Name = 'Portal Customer A'
      LIMIT 1
    ]
    .Name;
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    Test.startTest();
    System.runAs(visitor) {
      for (Integer i = 0; i < 5; i++) {
        Map<String, Object> attempt = PortalGuestService.lookup(
          normalizedNumber,
          '000' + i,
          '203.0.113.3'
        );
        Assert.areEqual(
          i == 4 ? 'LOCKED' : 'NOT_FOUND',
          attempt.get('outcome'),
          'The fifth failed guess starts the lock.'
        );
      }
      Assert.areEqual(
        'LOCKED',
        PortalGuestService.lookup(normalizedNumber, '4567', '203.0.113.3')
          .get('outcome'),
        'Correct proof must respect the active lock.'
      );
      Assert.areEqual(
        'FOUND',
        PortalGuestService.lookup(normalizedNumber, '4567', '203.0.113.4')
          .get('outcome'),
        'A different source must not inherit another visitor\'s lock.'
      );
    }
    Test.stopTest();
    List<Portal_Lookup_Limit__c> counters = [
      SELECT Fingerprint__c
      FROM Portal_Lookup_Limit__c
    ];
    Assert.areEqual(
      2,
      counters.size(),
      'Different phone guesses must share the same pair counter.'
    );
    Assert.areEqual(
      64,
      counters[0].Fingerprint__c.length(),
      'Only a digest is stored.'
    );
  }

  @IsTest
  static void expiredLockAllowsLookupAgain() {
    String normalizedNumber = [
      SELECT Name
      FROM Return_Request__c
      WHERE Customer__r.Name = 'Portal Customer A'
      LIMIT 1
    ]
    .Name;
    String fingerprint = EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(
          UserInfo.getOrganizationId() + '|203.0.113.5|' + normalizedNumber
        )
      )
    );
    insert as system new Portal_Lookup_Limit__c(
      Fingerprint__c = fingerprint,
      Failure_Count__c = 5,
      Window_Started_At__c = System.now().addMinutes(-31),
      Locked_Until__c = System.now().addMinutes(-1)
    );
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    Test.startTest();
    System.runAs(visitor) {
      Assert.areEqual(
        'FOUND',
        PortalGuestService.lookup(normalizedNumber, '4567', '203.0.113.5')
          .get('outcome'),
        'Expired locks must not permanently deny a customer.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void unprivilegedCallerIsDenied() {
    Test.startTest();
    try {
      PortalGuestService.lookup('RR-UNKNOWN', '0000', '203.0.113.6');
      Assert.fail('The entry-point permission is required.');
    } catch (ReturnPortalDomain.PortalException e) {
      Assert.isTrue(
        e.getMessage().contains('quyền'),
        'Deny before accessing records.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void missingSourceFailsClosed() {
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    Test.startTest();
    System.runAs(visitor) {
      try {
        PortalGuestService.lookup('RR-UNKNOWN', '0000', null);
        Assert.fail(
          'Unverified source identities must not bypass rate limits.'
        );
      } catch (ReturnPortalDomain.PortalException e) {
        Assert.isTrue(
          e.getMessage().contains('nguồn'),
          'Missing transport identity must be rejected.'
        );
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void restRejectsClientSuppliedSource() {
    User visitor = [
      SELECT Id
      FROM User
      WHERE LastName = 'Portal Guest Actor'
      LIMIT 1
    ];
    RestContext.request = new RestRequest();
    RestContext.request.requestBody = Blob.valueOf(
      '{"requestNumber":"RR-UNKNOWN","phoneSuffix":"0000","sourceAddress":"spoofed"}'
    );
    RestContext.response = new RestResponse();
    Test.startTest();
    System.runAs(visitor) {
      PortalGuestRest.lookup();
    }
    Test.stopTest();
    Assert.areEqual(
      400,
      RestContext.response.statusCode,
      'Strict request shape rejects a forged source argument.'
    );
    Assert.isTrue(
      RestContext.response.responseBody.toString().contains('INVALID_INPUT'),
      'Do not return parser details.'
    );
  }
}
