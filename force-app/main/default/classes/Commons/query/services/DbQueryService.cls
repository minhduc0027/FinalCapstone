public with sharing class DbQueryService {
  private static final Integer MAX_RECORDS_PER_TX = 49999;
  /** Executes with built-in pagination strategies and a server-owned page cap. */
  public static DbQueryResult execute(DbQueryRequest request, Integer maxRows) {
    return execute(request, maxRows, new DbPageStrategyFactory());
  }
  /** Uses a caller-supplied strategy factory without changing the global registry. */
  public static DbQueryResult execute(
    DbQueryRequest request,
    Integer maxRows,
    DbPageStrategyFactory factory
  ) {
    if (request == null) {
      throw new DbQueryException('Query request is required');
    }

    Integer size = effectiveSize(request.pageSize, maxRows);
    DbPageRequest page = request.page == null
      ? new DbPageRequest()
      : request.page;

    String strategy = String.isBlank(page.strategy)
      ? DbPageRequest.OFFSET
      : page.strategy.trim().toUpperCase();

    if (factory == null) {
      throw new DbQueryException('Page strategy factory is required');
    }
    IDbPageStrategy implementation = factory.resolve(strategy);
    if (implementation == null) {
      throw new DbQueryException('Page strategy is required');
    }

    DbQueryPlan plan = DbQueryCompiler.compile(request);
    return implementation.execute(plan, page, size);
  }

  public static Database.QueryLocator queryLocator(DbQueryRequest request) {
    if (request == null) {
      throw new DbQueryException('Query request is required');
    }

    if (request.page != null || request.pageSize != null) {
      throw new DbQueryException(
        'QueryLocator uses batch scope, not page or pageSize'
      );
    }

    DbQueryPlan plan = DbQueryCompiler.compile(request);
    try {
      return Database.getQueryLocatorWithBinds(
        plan.toSoql(),
        plan.binds,
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw new DbQueryException(
        'Unable to open query locator: ' + e.getMessage(),
        e
      );
    }
  }

  public static DbQueryResult fetchPage(
    Database.PaginationCursor cursor,
    Integer position,
    Integer pageSize,
    Integer maxRows
  ) {
    Integer size = effectiveSize(pageSize, maxRows);
    return new DbPageCursorStrategy().fetch(cursor, position, size);
  }

  public static DbQueryResult queryPage(
    DbQueryPlan plan,
    String soql,
    Integer pageSize
  ) {
    try {
      DbQueryResult result = new DbQueryResult();

      result.records = Database.queryWithBinds(
        soql,
        plan.binds,
        AccessLevel.USER_MODE
      );

      result.hasNext = result.records.size() > pageSize;

      if (result.hasNext) {
        result.records.remove(result.records.size() - 1);
      }

      result.soql = soql;
      result.bindCount = plan.binds.size();

      return result;
    } catch (Exception e) {
      throw new DbQueryException(
        'User-mode query failed: ' + e.getMessage(),
        e
      );
    }
  }

  public static Integer effectiveSize(Integer pageSize, Integer maxRows) {
    if (pageSize == null || pageSize <= 0 || maxRows == null || maxRows <= 0) {
      throw new DbQueryException('pageSize and maxRows must be positive');
    }

    Integer size = Math.min(pageSize, maxRows);
    if (size > MAX_RECORDS_PER_TX) {
      throw new DbQueryException(
        'Page size cannot exceed ' + MAX_RECORDS_PER_TX
      );
    }

    return size;
  }

  public static void requireRows(Integer count) {
    if (Limits.getLimitQueryRows() - Limits.getQueryRows() < count) {
      throw new DbQueryException(
        'Insufficient query-row budget for requested page'
      );
    }
  }
}
