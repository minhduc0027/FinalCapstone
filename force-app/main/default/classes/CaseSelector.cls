public with sharing class CaseSelector {
  private static final List<String> BASE_FIELDS = new List<String>{
    'Id',
    'CaseNumber',
    'Subject',
    'Status',
    'Priority',
    'AccountId',
    'OwnerId',
    'Origin',
    'CreatedById',
    'CreatedDate'
  };

  private static final List<String> CREATOR_FIELDS = new List<String>{
    'Id',
    'CaseNumber',
    'Status',
    'Priority',
    'CreatedById',
    'CreatedBy.Email'
  };

  private static final List<String> ACCOUNT_FIELDS = new List<String>{
    'Id',
    'Name',
    'AccountTier__c'
  };

  private static final List<String> CASE_HISTORY_FIELDS = new List<String>{
    'Id',
    'Field',
    'OldValue',
    'NewValue',
    'CreatedDate',
    'CreatedBy.Id',
    'CreatedBy.Name'
  };

  private static final List<String> CLOSED_CASE_FIELDS = new List<String>{
    'Id',
    'CaseNumber',
    'Status',
    'ClosedDate'
  };

  private static final List<String> STATUS_FIELDS = new List<String>{
    'Id',
    'Status'
  };

  /*
   * Accounts
   */
  public static Map<Id, Account> selectAccountsByIds(Set<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new Map<Id, Account>();
    }

    ReportRequest request = createRequest('Account', ACCOUNT_FIELDS);

    request.filters.add(new FilterCondition('Id', 'IN', accountIds));

    request.limitSize = accountIds.size();

    ReportResult result = GenericSelector.selectRecords(
      request,
      accountIds.size()
    );

    return new Map<Id, Account>(toAccountList(result.records));
  }

  /*
   * Single Case
   */
  public static Case selectById(Id caseId) {
    if (caseId == null) {
      return null;
    }

    ReportRequest request = createRequest('Case', BASE_FIELDS);

    request.filters.add(new FilterCondition('Id', '=', caseId));

    request.limitSize = 1;

    ReportResult result = GenericSelector.selectRecords(request, 1);

    return result.records.isEmpty() ? null : (Case) result.records[0];
  }

  /*
   * Multiple Cases
   */
  public static List<Case> selectByIds(Set<Id> caseIds) {
    if (caseIds == null || caseIds.isEmpty()) {
      return new List<Case>();
    }
    ReportRequest request = createRequest('Case', BASE_FIELDS);
    request.filters.add(new FilterCondition('Id', 'IN', caseIds));
    request.limitSize = caseIds.size();

    ReportResult result = GenericSelector.selectRecords(
      request,
      caseIds.size()
    );

    return toCaseList(result.records);
  }

  public static List<CaseHistory> selectCaseHistory(Id caseId) {
    return [
      SELECT
        Id,
        Field,
        OldValue,
        NewValue,
        CreatedDate,
        CreatedBy.Id,
        CreatedBy.Name
      FROM CaseHistory
      WHERE CaseId = :caseId
      ORDER BY CreatedDate DESC
    ];
  }
  /*
    public static List<CaseHistory> selectCaseHistory(Id caseId){
        ReportRequest request = createRequest('CaseHistory', CASE_HISTORY_FIELDS);
        request.orderByFields = new List<String>{'CreatedDate', 'Id'};
        request.orderDesc = true;
        request.limitSize = Math.min(
            safePageSize,
            remainingQueryRows
        );
        request.filters.add(
            new FilterCondition('CaseId', '=', caseId)
        );
        ReportResult result =
            GenericSelector.selectRecords(request, request.limitSize);

        List<CaseHistory> cases = new List<CaseHistory>();
        if (records == null) {
            return cases;
        }
        for (SObject record : records) {
            cases.add((CaseHistory) record);
        }
        return cases;
    }*/

  /*
   * Map version
   */
  public static Map<Id, Case> selectMapByIds(Set<Id> caseIds) {
    return new Map<Id, Case>(selectByIds(caseIds));
  }

  /*
   * Generic Case search
   */
  public static List<Case> selectCases(
    String status,
    String priority,
    Id ownerId,
    Boolean openOnly,
    Integer pageSize,
    Datetime cursorCreatedDate,
    Id cursorId
  ) {
    ReportRequest request = createRequest('Case', BASE_FIELDS);
    if (String.isNotBlank(status)) {
      request.filters.add(new FilterCondition('Status', '=', status.trim()));
    }
    if (String.isNotBlank(priority)) {
      request.filters.add(
        new FilterCondition('Priority', '=', priority.trim())
      );
    }
    if (ownerId != null) {
      request.filters.add(new FilterCondition('OwnerId', '=', ownerId));
    }
    if (openOnly == true) {
      request.filters.add(new FilterCondition('IsClosed', '=', false));
    }

    Integer safePageSize = normalizePageSize(pageSize);
    Integer remainingQueryRows = getRemainingQueryRowLimit();

    request.limitSize = Math.min(safePageSize, remainingQueryRows);

    request.orderByFields = new List<String>{ 'CreatedDate', 'Id' };
    request.orderDesc = true;

    //validateCursor(cursorCreatedDate, cursorId);

    if (cursorCreatedDate != null) {
      request.keysetCursor = new KeysetCursor(
        'CreatedDate',
        cursorCreatedDate,
        cursorId,
        true
      );
    }

    ReportResult result = GenericSelector.selectRecords(
      request,
      request.limitSize
    );

    return toCaseList(result.records);
  }

  /*
   * Notification service
   */
  public static List<Case> selectCasesWithCreator(Set<Id> caseIds) {
    if (caseIds == null || caseIds.isEmpty()) {
      return new List<Case>();
    }
    ReportRequest request = createRequest('Case', CREATOR_FIELDS);
    request.filters.add(new FilterCondition('Id', 'IN', caseIds));

    request.limitSize = caseIds.size();
    ReportResult result = GenericSelector.selectRecords(
      request,
      caseIds.size()
    );

    return toCaseList(result.records);
  }

  private static void addCaseSearchFilters(
    ReportRequest request,
    String status,
    String priority,
    Id ownerId,
    Boolean openOnly
  ) {
    if (String.isNotBlank(status)) {
      request.filters.add(new FilterCondition('Status', '=', status.trim()));
    }

    if (String.isNotBlank(priority)) {
      request.filters.add(
        new FilterCondition('Priority', '=', priority.trim())
      );
    }

    if (ownerId != null) {
      request.filters.add(new FilterCondition('OwnerId', '=', ownerId));
    }

    if (openOnly == true) {
      request.filters.add(new FilterCondition('IsClosed', '=', false));
    }
  }

  public static Integer countCases(
    String status,
    String priority,
    Id ownerId,
    Boolean openOnly
  ) {
    ReportRequest request = createRequest('Case', new List<String>{ 'Id' });
    addCaseSearchFilters(request, status, priority, ownerId, openOnly);
    return GenericSelector.countRecords(request);
  }

  public static Case selectStatusById(Id caseId) {
    if (caseId == null) {
      return null;
    }

    ReportRequest request = createRequest('Case', STATUS_FIELDS);
    request.filters.add(new FilterCondition('Id', '=', caseId));

    request.limitSize = 1;
    ReportResult result = GenericSelector.selectRecords(request, 1);

    return result.records.isEmpty() ? null : (Case) result.records[0];
  }

  /*
   * Creates the common request structure.
   */
  private static ReportRequest createRequest(
    String objectName,
    List<String> fields
  ) {
    ReportRequest request = new ReportRequest();
    request.objectName = objectName;
    request.fields = fields.clone();
    request.filters = new List<FilterCondition>();
    request.orderDesc = false;
    return request;
  }

  /*
   * Converts List<SObject> returned by GenericSelector
   * to a strongly typed List<Case>.
   */
  private static List<Case> toCaseList(List<SObject> records) {
    List<Case> cases = new List<Case>();
    if (records == null) {
      return cases;
    }
    for (SObject record : records) {
      cases.add((Case) record);
    }
    return cases;
  }

  /*
   * Converts List<SObject> returned by GenericSelector
   * to a strongly typed List<Account>.
   */
  private static List<Account> toAccountList(List<SObject> records) {
    List<Account> accounts = new List<Account>();
    if (records == null) {
      return accounts;
    }
    for (SObject record : records) {
      accounts.add((Account) record);
    }
    return accounts;
  }

  /*
   * This is a governor-limit ceiling, not the configurable
   * report-engine MaxRows value.
   *
   * ConfigReportService must still read ReportConfig__c and
   * pass its MaxRows value directly to GenericSelector.
   */
  private static Integer getRemainingQueryRowLimit() {
    Integer remainingRows = Limits.getLimitQueryRows() - Limits.getQueryRows();
    if (remainingRows <= 0) {
      throw new ConfigReportException(
        'No query rows remain in the current transaction.'
      );
    }
    return remainingRows;
  }

  private static Integer normalizePageSize(Integer pageSize) {
    if (pageSize == null || pageSize < 1) {
      return 10;
    }
    return Math.min(pageSize, 200);
  }
}
