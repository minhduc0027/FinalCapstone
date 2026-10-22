public with sharing class DbPageCursorStrategy implements IDbPageStrategy {
  private static final Integer MAX_PER_PAGE = 2000;
  public DbQueryResult execute(
    DbQueryPlan plan,
    DbPageRequest page,
    Integer pageSize
  ) {
    if (page.offsetSize != null && page.offsetSize != 0) {
      throw new DbQueryException('PAGE_CURSOR does not accept offsetSize');
    }
    if (page.afterId != null || page.afterValue != null) {
      throw new DbQueryException(
        'PAGE_CURSOR does not accept keyset continuation'
      );
    }

    validatePageSize(pageSize);

    String soql = plan.toSoql();
    try {
      Database.PaginationCursor cursor = Database.getPaginationCursorWithBinds(
        soql,
        plan.binds,
        AccessLevel.USER_MODE
      );

      DbQueryResult result = fetch(cursor, 0, pageSize);
      result.soql = soql;
      result.bindCount = plan.binds.size();
      return result;
    } catch (DbQueryException e) {
      throw e;
    } catch (Exception e) {
      throw new DbQueryException(
        'Unable to open pagination cursor: ' + e.getMessage(),
        e
      );
    }
  }

  public DbQueryResult fetch(
    Database.PaginationCursor cursor,
    Integer position,
    Integer pageSize
  ) {
    if (cursor == null) {
      throw new DbQueryException('Pagination cursor is required');
    }
    if (position == null || position < 0) {
      throw new DbQueryException('Cursor position must be non-negative');
    }

    validatePageSize(pageSize);

    try {
      DbQueryResult result = new DbQueryResult();
      result.strategy = DbPageRequest.PAGE_CURSOR;
      result.cursor = cursor;
      result.records = new List<SObject>();
      result.hasNext = false;
      result.totalRecords = cursor.getNumRecords();

      if (position > result.totalRecords) {
        throw new DbQueryException('Cursor position exceeds result size');
      }

      if (position == result.totalRecords) {
        return result;
      }

      Integer fetchSize = Math.min(pageSize, result.totalRecords - position);
      DbQueryService.requireRows(fetchSize);

      Database.CursorFetchResult fetched = cursor.fetchPage(
        position,
        fetchSize
      );
      result.records = fetched.getRecords();

      Integer nextIndex = fetched.getNextIndex();
      result.hasNext =
        nextIndex != null &&
        nextIndex > position &&
        nextIndex < result.totalRecords;

      if (result.hasNext) {
        result.nextPosition = nextIndex;
      }

      return result;
    } catch (DbQueryException e) {
      throw e;
    } catch (Exception e) {
      throw new DbQueryException(
        'Unable to fetch cursor page; ' +
          'restart the query if expired: ' +
          e.getMessage(),
        e
      );
    }
  }

  private static void validatePageSize(Integer pageSize) {
    if (pageSize == null || pageSize <= 0) {
      throw new DbQueryException('Page size must be positive');
    }
    if (pageSize > MAX_PER_PAGE) {
      throw new DbQueryException(
        'Pagination cursor page size cannot exceed ' + MAX_PER_PAGE
      );
    }
  }
}
