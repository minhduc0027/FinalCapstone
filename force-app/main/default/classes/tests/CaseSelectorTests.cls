@IsTest
private class CaseSelectorTests {
  private static final String ACCOUNT_NAME = 'CaseSelector Test Account';

  private static final String SUBJECT_PREFIX = 'CaseSelector Test - ';

  /*
   * Không hard-code toàn bộ Status/Priority vì các giá trị
   * có thể được cấu hình khác nhau giữa các org.
   */
  @TestSetup
  static void setupData() {
    Account testAccount = new Account(Name = ACCOUNT_NAME);
    insert testAccount;

    String openStatus = getOpenStatus();
    String closedStatus = getClosedStatus();
    String priority = getPriority();

    List<Case> casesToInsert = new List<Case>();

    for (Integer index = 1; index <= 4; index++) {
      casesToInsert.add(
        new Case(
          Subject = SUBJECT_PREFIX + index,
          Status = openStatus,
          Priority = priority,
          Origin = 'Web',
          AccountId = testAccount.Id,
          OwnerId = UserInfo.getUserId()
        )
      );
    }

    /*
     * Tạo một Case rồi chuyển sang trạng thái closed.
     * Khi Case chuyển sang trạng thái đóng, Salesforce
     * tự thiết lập ClosedDate.
     */
    casesToInsert.add(
      new Case(
        Subject = SUBJECT_PREFIX + 'Closed',
        Status = openStatus,
        Priority = priority,
        Origin = 'Web',
        AccountId = testAccount.Id,
        OwnerId = UserInfo.getUserId()
      )
    );

    insert casesToInsert;

    Case closedCase = casesToInsert[casesToInsert.size() - 1];
    closedCase.Status = closedStatus;
    update closedCase;

    /*
     * Tạo thêm một lần thay đổi Status để CaseHistory
     * có thể có dữ liệu nếu org bật field history tracking.
     *
     * Test không phụ thuộc vào việc tracking đang bật.
     */
    if (openStatus != closedStatus) {
      Case historyCase = casesToInsert[0];
      historyCase.Status = closedStatus;
      update historyCase;
    }
  }

  /*
   * =========================================================
   * Metadata helpers
   * =========================================================
   */

  private static String getOpenStatus() {
    List<CaseStatus> statuses = [
      SELECT MasterLabel, IsClosed
      FROM CaseStatus
      WHERE IsClosed = FALSE
      ORDER BY SortOrder
      LIMIT 1
    ];

    System.assert(
      !statuses.isEmpty(),
      'The org must contain at least one open Case status.'
    );

    return statuses[0].MasterLabel;
  }

  private static String getClosedStatus() {
    List<CaseStatus> statuses = [
      SELECT MasterLabel, IsClosed
      FROM CaseStatus
      WHERE IsClosed = TRUE
      ORDER BY SortOrder
      LIMIT 1
    ];

    System.assert(
      !statuses.isEmpty(),
      'The org must contain at least one closed Case status.'
    );

    return statuses[0].MasterLabel;
  }

  private static Account getTestAccount() {
    return [
      SELECT Id, Name
      FROM Account
      WHERE Name = :ACCOUNT_NAME
      LIMIT 1
    ];
  }

  private static List<Case> getTestCases() {
    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Status,
        Priority,
        AccountId,
        OwnerId,
        IsClosed,
        CreatedDate,
        ClosedDate
      FROM Case
      WHERE Subject LIKE :SUBJECT_PREFIX + '%'
      ORDER BY CreatedDate DESC, Id DESC
    ];
  }

  /*
   * =========================================================
   * selectAccountsByIds
   * =========================================================
   */

  @IsTest
  static void selectAccountsByIds_shouldReturnEmptyForNullInput() {
    Test.startTest();

    Map<Id, Account> result = CaseSelector.selectAccountsByIds(null);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectAccountsByIds_shouldReturnEmptyForEmptySet() {
    Test.startTest();

    Map<Id, Account> result = CaseSelector.selectAccountsByIds(new Set<Id>());

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectAccountsByIds_shouldReturnRequestedAccount() {
    Account testAccount = getTestAccount();

    Test.startTest();

    Map<Id, Account> result = CaseSelector.selectAccountsByIds(
      new Set<Id>{ testAccount.Id }
    );

    Test.stopTest();

    System.assertEquals(1, result.size());
    System.assert(result.containsKey(testAccount.Id));

    Account selectedAccount = result.get(testAccount.Id);

    System.assertEquals(ACCOUNT_NAME, selectedAccount.Name);

    /*
     * Xác nhận field custom đã được SELECT.
     * Giá trị có thể null nhưng field phải populated.
     */
    System.assert(
      selectedAccount.getPopulatedFieldsAsMap().containsKey('Name')
    );
  }

  /*
   * =========================================================
   * selectById
   * =========================================================
   */

  @IsTest
  static void selectById_shouldReturnNullForNullId() {
    Test.startTest();

    Case result = CaseSelector.selectById(null);

    Test.stopTest();

    System.assertEquals(null, result);
  }

  @IsTest
  static void selectById_shouldReturnRequestedCase() {
    Case expectedCase = getTestCases()[0];

    Test.startTest();

    Case result = CaseSelector.selectById(expectedCase.Id);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(expectedCase.Id, result.Id);
    System.assertEquals(expectedCase.Subject, result.Subject);
    System.assertEquals(expectedCase.AccountId, result.AccountId);
    System.assertEquals(expectedCase.OwnerId, result.OwnerId);
  }

  @IsTest
  static void selectById_shouldReturnNullWhenRecordDoesNotExist() {
    /*
     * Đây là valid Case Id format nhưng không tồn tại.
     */
    Id missingCaseId = (Id) '500000000000000AAA';

    Test.startTest();

    Case result = CaseSelector.selectById(missingCaseId);

    Test.stopTest();

    System.assertEquals(null, result);
  }

  /*
   * =========================================================
   * selectByIds
   * =========================================================
   */

  @IsTest
  static void selectByIds_shouldReturnEmptyForNullInput() {
    Test.startTest();

    List<Case> result = CaseSelector.selectByIds(null);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectByIds_shouldReturnEmptyForEmptySet() {
    Test.startTest();

    List<Case> result = CaseSelector.selectByIds(new Set<Id>());

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectByIds_shouldReturnRequestedCases() {
    List<Case> testCases = getTestCases();

    Set<Id> requestedIds = new Set<Id>{ testCases[0].Id, testCases[1].Id };

    Test.startTest();

    List<Case> result = CaseSelector.selectByIds(requestedIds);

    Test.stopTest();

    System.assertEquals(2, result.size());

    Set<Id> actualIds = new Map<Id, Case>(result).keySet();

    System.assertEquals(requestedIds, actualIds);
  }

  /*
   * =========================================================
   * selectMapByIds
   * =========================================================
   */

  @IsTest
  static void selectMapByIds_shouldReturnCasesAsMap() {
    List<Case> testCases = getTestCases();

    Set<Id> requestedIds = new Set<Id>{
      testCases[0].Id,
      testCases[1].Id,
      testCases[2].Id
    };

    Test.startTest();

    Map<Id, Case> result = CaseSelector.selectMapByIds(requestedIds);

    Test.stopTest();

    System.assertEquals(3, result.size());

    for (Id caseId : requestedIds) {
      System.assert(
        result.containsKey(caseId),
        'Expected Case was not found: ' + caseId
      );
    }
  }

  @IsTest
  static void selectMapByIds_shouldReturnEmptyMapForNullInput() {
    Test.startTest();

    Map<Id, Case> result = CaseSelector.selectMapByIds(null);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  /*
   * =========================================================
   * selectCases
   * =========================================================
   */

  @IsTest
  static void selectCases_shouldReturnCasesWithoutFilters() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      20,
      null,
      null
    );

    Test.stopTest();

    System.assert(result.size() >= 5, 'Expected test Cases to be returned.');

    assertDescendingOrder(result);
  }

  @IsTest
  static void selectCases_shouldApplyAllFilters() {
    List<Case> testCases = getTestCases();

    Case expectedCase;

    for (Case caseRecord : testCases) {
      if (!caseRecord.IsClosed) {
        expectedCase = caseRecord;
        break;
      }
    }

    System.assertNotEquals(
      null,
      expectedCase,
      'Expected at least one open Case.'
    );

    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      '  ' + expectedCase.Status + '  ',
      '  ' + expectedCase.Priority + '  ',
      expectedCase.OwnerId,
      true,
      200,
      null,
      null
    );

    Test.stopTest();

    System.assert(!result.isEmpty(), 'Expected filtered Cases.');

    for (Case caseRecord : result) {
      System.assertEquals(expectedCase.Status, caseRecord.Status);

      System.assertEquals(expectedCase.Priority, caseRecord.Priority);

      System.assertEquals(expectedCase.OwnerId, caseRecord.OwnerId);

      /*
       * IsClosed không nằm trong BASE_FIELDS,
       * vì vậy xác minh bằng Status.
       */
      System.assertNotEquals(getClosedStatus(), caseRecord.Status);
    }
  }

  @IsTest
  static void selectCases_shouldUseDefaultPageSize() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      null,
      null,
      null
    );

    Test.stopTest();

    System.assert(result.size() <= 10, 'Null page size should default to 10.');
  }

  @IsTest
  static void selectCases_shouldUseDefaultForZeroPageSize() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      0,
      null,
      null
    );

    Test.stopTest();

    System.assert(result.size() <= 10, 'Zero page size should default to 10.');
  }

  @IsTest
  static void selectCases_shouldCapPageSizeAtTwoHundred() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      500,
      null,
      null
    );

    Test.stopTest();

    System.assert(result.size() <= 200, 'Page size should be capped at 200.');
  }

  @IsTest
  static void selectCases_shouldSupportKeysetCursor() {
    List<Case> firstPage = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      2,
      null,
      null
    );

    System.assertEquals(
      2,
      firstPage.size(),
      'First page should contain two Cases.'
    );

    Case cursorRecord = firstPage[firstPage.size() - 1];

    Test.startTest();

    List<Case> secondPage = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      2,
      cursorRecord.CreatedDate,
      cursorRecord.Id
    );

    Test.stopTest();

    System.assertNotEquals(null, secondPage);

    for (Case caseRecord : secondPage) {
      Boolean isAfterCursor =
        caseRecord.CreatedDate < cursorRecord.CreatedDate ||
        (caseRecord.CreatedDate == cursorRecord.CreatedDate &&
        caseRecord.Id < cursorRecord.Id);

      System.assert(
        isAfterCursor,
        'Second-page record must be after the descending cursor.'
      );
    }

    Set<Id> firstPageIds = new Map<Id, Case>(firstPage).keySet();

    for (Case caseRecord : secondPage) {
      System.assert(
        !firstPageIds.contains(caseRecord.Id),
        'Keyset pages must not overlap.'
      );
    }
  }

  /*
   * =========================================================
   * selectCasesWithCreator
   * =========================================================
   */

  @IsTest
  static void selectCasesWithCreator_shouldReturnEmptyForNullInput() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCasesWithCreator(null);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectCasesWithCreator_shouldReturnEmptyForEmptySet() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCasesWithCreator(new Set<Id>());

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectCasesWithCreator_shouldIncludeCreatorEmail() {
    Case testCase = getTestCases()[0];

    Test.startTest();

    List<Case> result = CaseSelector.selectCasesWithCreator(
      new Set<Id>{ testCase.Id }
    );

    Test.stopTest();

    System.assertEquals(1, result.size());

    Case selectedCase = result[0];

    System.assertEquals(testCase.Id, selectedCase.Id);

    System.assertNotEquals(null, selectedCase.CreatedBy);

    System.assertEquals(UserInfo.getUserId(), selectedCase.CreatedById);

    System.assertNotEquals(null, selectedCase.CreatedBy.Email);
  }

  /*
   * =========================================================
   * countCases
   * =========================================================
   */

  @IsTest
  static void countCases_shouldCountWithoutFilters() {
    Test.startTest();

    Integer result = CaseSelector.countCases(null, null, null, false);

    Test.stopTest();

    System.assert(result >= 5, 'Expected count to include test Cases.');
  }

  @IsTest
  static void countCases_shouldApplyAllFilters() {
    Case openCase;

    for (Case caseRecord : getTestCases()) {
      if (!caseRecord.IsClosed) {
        openCase = caseRecord;
        break;
      }
    }

    System.assertNotEquals(null, openCase);

    Test.startTest();

    Integer result = CaseSelector.countCases(
      '  ' + openCase.Status + '  ',
      '  ' + openCase.Priority + '  ',
      openCase.OwnerId,
      true
    );

    Test.stopTest();

    Integer expectedCount = [
      SELECT COUNT()
      FROM Case
      WHERE
        Status = :openCase.Status
        AND Priority = :openCase.Priority
        AND OwnerId = :openCase.OwnerId
        AND IsClosed = FALSE
    ];

    System.assertEquals(expectedCount, result);
  }

  /*
   * =========================================================
   * selectStatusById
   * =========================================================
   */

  @IsTest
  static void selectStatusById_shouldReturnNullForNullId() {
    Test.startTest();

    Case result = CaseSelector.selectStatusById(null);

    Test.stopTest();

    System.assertEquals(null, result);
  }

  @IsTest
  static void selectStatusById_shouldReturnOnlyRequiredData() {
    Case expectedCase = getTestCases()[0];

    Test.startTest();

    Case result = CaseSelector.selectStatusById(expectedCase.Id);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(expectedCase.Id, result.Id);
    System.assertEquals(expectedCase.Status, result.Status);

    Map<String, Object> populatedFields = result.getPopulatedFieldsAsMap();

    System.assert(populatedFields.containsKey('Id'));

    System.assert(populatedFields.containsKey('Status'));

    System.assert(
      !populatedFields.containsKey('Subject'),
      'selectStatusById should not query Subject.'
    );
  }

  @IsTest
  static void selectStatusById_shouldReturnNullWhenMissing() {
    Id missingCaseId = (Id) '500000000000000AAA';

    Test.startTest();

    Case result = CaseSelector.selectStatusById(missingCaseId);

    Test.stopTest();

    System.assertEquals(null, result);
  }

  /*
   * =========================================================
   * selectCaseHistory
   * =========================================================
   */

  @IsTest
  static void selectCaseHistory_shouldExecuteForCase() {
    Case testCase = getTestCases()[0];

    Test.startTest();

    List<CaseHistory> result = CaseSelector.selectCaseHistory(testCase.Id);

    Test.stopTest();

    System.assertNotEquals(null, result);

    Datetime previousCreatedDate;

    for (CaseHistory historyRecord : result) {
      if (previousCreatedDate != null) {
        System.assert(
          previousCreatedDate >= historyRecord.CreatedDate,
          'History must be ordered newest first.'
        );
      }

      previousCreatedDate = historyRecord.CreatedDate;

      System.assertNotEquals(null, historyRecord.CreatedBy);
    }
  }

  @IsTest
  static void selectCaseHistory_shouldReturnEmptyForNullId() {
    Test.startTest();

    List<CaseHistory> result = CaseSelector.selectCaseHistory(null);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  /*
   * =========================================================
   * Assertion helpers
   * =========================================================
   */

  private static void assertDescendingOrder(List<Case> records) {
    if (records.size() < 2) {
      return;
    }

    for (Integer index = 1; index < records.size(); index++) {
      Case previousRecord = records[index - 1];

      Case currentRecord = records[index];

      Boolean correctlyOrdered =
        previousRecord.CreatedDate > currentRecord.CreatedDate ||
        (previousRecord.CreatedDate == currentRecord.CreatedDate &&
        previousRecord.Id > currentRecord.Id);

      System.assert(
        correctlyOrdered,
        'Cases must be ordered by CreatedDate DESC, Id DESC.'
      );
    }
  }
}
