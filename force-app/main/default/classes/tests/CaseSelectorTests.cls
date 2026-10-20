@IsTest
private class CaseSelectorTests {
  private static final String SUBJECT_PREFIX = 'CaseSelectorTest-';

  private static final String OPEN_STATUS = 'New';
  private static final String CLOSED_STATUS = 'Closed';
  private static final String PRIORITY = 'Medium';
  private static final String ORIGIN = 'Web';

  @TestSetup
  static void setupData() {
    List<Case> casesToInsert = new List<Case>();

    for (Integer index = 1; index <= 5; index++) {
      casesToInsert.add(
        new Case(
          Subject = SUBJECT_PREFIX + index,
          Status = OPEN_STATUS,
          Priority = PRIORITY,
          Origin = ORIGIN
        )
      );
    }

    insert casesToInsert;

    /*
     * Tạo Case đã đóng để test:
     * - selectClosedCasesLast30Days()
     * - openOnly
     * - CaseHistory nếu Status history tracking được bật.
     */
    Case closedCase = casesToInsert[4];
    closedCase.Status = CLOSED_STATUS;
    update closedCase;
  }

  private static List<Case> getTestCases() {
    String subjectPattern = SUBJECT_PREFIX + '%';

    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Status,
        Priority,
        OwnerId,
        IsClosed,
        CreatedById,
        CreatedDate,
        ClosedDate
      FROM Case
      WHERE Subject LIKE :subjectPattern
      ORDER BY CreatedDate DESC, Id DESC
    ];
  }

  private static Case getOpenTestCase() {
    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Status,
        Priority,
        OwnerId,
        IsClosed,
        CreatedById,
        CreatedDate
      FROM Case
      WHERE Subject LIKE :SUBJECT_PREFIX + '%' AND IsClosed = FALSE
      LIMIT 1
    ];
  }

  private static Case getClosedTestCase() {
    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Status,
        Priority,
        OwnerId,
        IsClosed,
        CreatedById,
        CreatedDate,
        ClosedDate
      FROM Case
      WHERE Subject LIKE :SUBJECT_PREFIX + '%' AND IsClosed = TRUE
      LIMIT 1
    ];
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

    System.assertEquals(null, result, 'Null Case Id should return null.');
  }

  @IsTest
  static void selectById_shouldReturnCase() {
    Case expectedCase = getOpenTestCase();

    Test.startTest();

    Case result = CaseSelector.selectById(expectedCase.Id);

    Test.stopTest();

    System.assertNotEquals(null, result);

    System.assertEquals(expectedCase.Id, result.Id);

    System.assertEquals(expectedCase.Subject, result.Subject);

    System.assertEquals(expectedCase.Status, result.Status);

    System.assertEquals(expectedCase.Priority, result.Priority);

    System.assertEquals(expectedCase.OwnerId, result.OwnerId);

    System.assertEquals(expectedCase.CreatedById, result.CreatedById);
  }

  @IsTest
  static void selectById_shouldReturnNullForMissingCase() {
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
  static void selectByIds_shouldReturnEmptyForNullSet() {
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

    Set<Id> requestedIds = new Set<Id>{
      testCases[0].Id,
      testCases[1].Id,
      testCases[2].Id
    };

    Test.startTest();

    List<Case> result = CaseSelector.selectByIds(requestedIds);

    Test.stopTest();

    System.assertEquals(3, result.size());

    Map<Id, Case> resultById = new Map<Id, Case>(result);

    System.assertEquals(requestedIds, resultById.keySet());
  }

  /*
   * =========================================================
   * selectMapByIds
   * =========================================================
   */

  @IsTest
  static void selectMapByIds_shouldReturnEmptyForNullSet() {
    Test.startTest();

    Map<Id, Case> result = CaseSelector.selectMapByIds(null);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  @IsTest
  static void selectMapByIds_shouldReturnMap() {
    List<Case> testCases = getTestCases();

    Set<Id> requestedIds = new Set<Id>{ testCases[0].Id, testCases[1].Id };

    Test.startTest();

    Map<Id, Case> result = CaseSelector.selectMapByIds(requestedIds);

    Test.stopTest();

    System.assertEquals(2, result.size());

    System.assertEquals(requestedIds, result.keySet());

    for (Id caseId : requestedIds) {
      System.assertNotEquals(null, result.get(caseId));
    }
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

    System.assert(result.size() >= 5, 'Expected the test Cases.');

    assertDescendingOrder(result);
  }

  @IsTest
  static void selectCases_shouldApplyStatusFilter() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      '  ' + OPEN_STATUS + '  ',
      null,
      null,
      false,
      20,
      null,
      null
    );

    Test.stopTest();

    System.assert(!result.isEmpty());

    for (Case caseRecord : result) {
      System.assertEquals(OPEN_STATUS, caseRecord.Status);
    }
  }

  @IsTest
  static void selectCases_shouldApplyPriorityFilter() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      '  ' + PRIORITY + '  ',
      null,
      false,
      20,
      null,
      null
    );

    Test.stopTest();

    System.assert(!result.isEmpty());

    for (Case caseRecord : result) {
      System.assertEquals(PRIORITY, caseRecord.Priority);
    }
  }

  @IsTest
  static void selectCases_shouldApplyOwnerFilter() {
    Case testCase = getOpenTestCase();

    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      testCase.OwnerId,
      false,
      20,
      null,
      null
    );

    Test.stopTest();

    System.assert(!result.isEmpty());

    for (Case caseRecord : result) {
      System.assertEquals(testCase.OwnerId, caseRecord.OwnerId);
    }
  }

  @IsTest
  static void selectCases_shouldApplyOpenOnlyFilter() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      null,
      true,
      20,
      null,
      null
    );

    Test.stopTest();

    System.assert(!result.isEmpty());

    for (Case caseRecord : result) {
      System.assertNotEquals(
        CLOSED_STATUS,
        caseRecord.Status,
        'Closed Case should not be returned.'
      );
    }
  }

  @IsTest
  static void selectCases_shouldApplyAllFilters() {
    Case expectedCase = getOpenTestCase();

    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      '  ' + expectedCase.Status + '  ',
      '  ' + expectedCase.Priority + '  ',
      expectedCase.OwnerId,
      true,
      20,
      null,
      null
    );

    Test.stopTest();

    System.assert(!result.isEmpty());

    for (Case caseRecord : result) {
      System.assertEquals(expectedCase.Status, caseRecord.Status);

      System.assertEquals(expectedCase.Priority, caseRecord.Priority);

      System.assertEquals(expectedCase.OwnerId, caseRecord.OwnerId);

      System.assertNotEquals(CLOSED_STATUS, caseRecord.Status);
    }
  }

  /*
   * pageSize null hoặc < 1 phải được normalize thành 10.
   */
  @IsTest
  static void selectCases_shouldDefaultNullPageSize() {
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

    System.assert(result.size() <= 10);
  }

  @IsTest
  static void selectCases_shouldDefaultInvalidPageSize() {
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

    System.assert(result.size() <= 10);
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

    System.assert(result.size() <= 200);
  }

  @IsTest
  static void selectCases_shouldRespectPageSize() {
    Test.startTest();

    List<Case> result = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      2,
      null,
      null
    );

    Test.stopTest();

    System.assertEquals(2, result.size());
  }

  @IsTest
  static void selectCases_shouldSupportKeysetPagination() {
    List<Case> firstPage = CaseSelector.selectCases(
      null,
      null,
      null,
      false,
      2,
      null,
      null
    );

    System.assertEquals(2, firstPage.size());

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

    Set<Id> firstPageIds = new Map<Id, Case>(firstPage).keySet();

    for (Case caseRecord : secondPage) {
      System.assert(
        !firstPageIds.contains(caseRecord.Id),
        'Keyset pages must not overlap.'
      );

      Boolean isAfterCursor =
        caseRecord.CreatedDate < cursorRecord.CreatedDate ||
        (caseRecord.CreatedDate == cursorRecord.CreatedDate &&
        caseRecord.Id < cursorRecord.Id);

      System.assert(
        isAfterCursor,
        'Record is not after the descending cursor.'
      );
    }

    assertDescendingOrder(secondPage);
  }

  @IsTest
  static void selectCases_shouldRejectIncompleteCursor() {
    Case testCase = getOpenTestCase();

    try {
      CaseSelector.selectCases(
        null,
        null,
        null,
        false,
        10,
        testCase.CreatedDate,
        null
      );

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(
        ex.getMessage().contains('record Id must not be null'),
        ex.getMessage()
      );
    }
  }

  /*
   * =========================================================
   * selectCasesWithCreator
   * =========================================================
   */

  @IsTest
  static void selectCasesWithCreator_shouldReturnEmptyForNullSet() {
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
  static void selectCasesWithCreator_shouldReturnCreatorEmail() {
    Case expectedCase = getOpenTestCase();

    Test.startTest();

    List<Case> result = CaseSelector.selectCasesWithCreator(
      new Set<Id>{ expectedCase.Id }
    );

    Test.stopTest();

    System.assertEquals(1, result.size());

    Case selectedCase = result[0];

    System.assertEquals(expectedCase.Id, selectedCase.Id);

    System.assertEquals(expectedCase.CreatedById, selectedCase.CreatedById);

    System.assertNotEquals(null, selectedCase.CreatedBy);

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

    System.assert(result >= 5);
  }

  @IsTest
  static void countCases_shouldApplyAllFilters() {
    Case expectedCase = getOpenTestCase();

    Test.startTest();

    Integer result = CaseSelector.countCases(
      '  ' + expectedCase.Status + '  ',
      '  ' + expectedCase.Priority + '  ',
      expectedCase.OwnerId,
      true
    );

    Test.stopTest();

    Integer expectedCount = [
      SELECT COUNT()
      FROM Case
      WHERE
        Status = :expectedCase.Status
        AND Priority = :expectedCase.Priority
        AND OwnerId = :expectedCase.OwnerId
        AND IsClosed = FALSE
    ];

    System.assertEquals(expectedCount, result);
  }

  @IsTest
  static void countCases_shouldCountClosedCases() {
    Test.startTest();

    Integer result = CaseSelector.countCases(CLOSED_STATUS, null, null, false);

    Test.stopTest();

    Integer expectedCount = [
      SELECT COUNT()
      FROM Case
      WHERE Status = :CLOSED_STATUS
    ];

    System.assertEquals(expectedCount, result);

    System.assert(result >= 1);
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
  static void selectStatusById_shouldReturnStatus() {
    Case expectedCase = getOpenTestCase();

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
      'Subject should not be queried.'
    );
  }

  @IsTest
  static void selectStatusById_shouldReturnNullForMissingCase() {
    Id missingCaseId = (Id) '500000000000000AAA';

    Test.startTest();

    Case result = CaseSelector.selectStatusById(missingCaseId);

    Test.stopTest();

    System.assertEquals(null, result);
  }

  /*
   * =========================================================
   * selectClosedCasesLast30Days
   * =========================================================
   */

  @IsTest
  static void selectClosedCasesLast30Days_shouldReturnClosedCase() {
    Case expectedCase = getClosedTestCase();

    System.assertNotEquals(null, expectedCase.ClosedDate);

    Test.startTest();

    List<Case> result = CaseSelector.selectClosedCasesLast30Days();

    Test.stopTest();

    System.assertNotEquals(null, result);

    Map<Id, Case> resultById = new Map<Id, Case>(result);

    System.assert(
      resultById.containsKey(expectedCase.Id),
      'Recently closed test Case should be returned.'
    );

    Datetime rangeStart = Datetime.newInstance(
      Date.today().addDays(-30),
      Time.newInstance(0, 0, 0, 0)
    );

    Datetime previousClosedDate;

    for (Case caseRecord : result) {
      System.assertEquals(CLOSED_STATUS, caseRecord.Status);

      System.assertNotEquals(null, caseRecord.ClosedDate);

      System.assert(caseRecord.ClosedDate >= rangeStart);

      if (previousClosedDate != null) {
        System.assert(
          previousClosedDate >= caseRecord.ClosedDate,
          'Cases should be ordered by ClosedDate DESC.'
        );
      }

      previousClosedDate = caseRecord.ClosedDate;
    }
  }

  /*
   * =========================================================
   * selectCaseHistory
   * =========================================================
   */

  @IsTest
  static void selectCaseHistory_shouldReturnHistoryList() {
    Case closedCase = getClosedTestCase();

    Test.startTest();

    List<CaseHistory> result = CaseSelector.selectCaseHistory(closedCase.Id);

    Test.stopTest();

    System.assertNotEquals(null, result);

    Datetime previousCreatedDate;

    for (CaseHistory historyRecord : result) {
      if (previousCreatedDate != null) {
        System.assert(
          previousCreatedDate >= historyRecord.CreatedDate,
          'CaseHistory should be ordered by CreatedDate DESC.'
        );
      }

      previousCreatedDate = historyRecord.CreatedDate;

      System.assertNotEquals(null, historyRecord.Id);

      System.assertNotEquals(null, historyRecord.CreatedBy);

      System.assertNotEquals(null, historyRecord.CreatedBy.Id);

      System.assertNotEquals(null, historyRecord.CreatedBy.Name);
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
    for (Integer index = 1; index < records.size(); index++) {
      Case previousRecord = records[index - 1];

      Case currentRecord = records[index];

      Boolean correctlyOrdered =
        previousRecord.CreatedDate > currentRecord.CreatedDate ||
        (previousRecord.CreatedDate == currentRecord.CreatedDate &&
        previousRecord.Id > currentRecord.Id);

      System.assert(
        correctlyOrdered,
        'Expected CreatedDate DESC, Id DESC ordering.'
      );
    }
  }
}
