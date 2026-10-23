public with sharing class DbOffsetStrategy implements IDbPageStrategy {
  private static final Integer MAX_OFFSET = 2000;
  public DbQueryResult execute(
    DbQueryPlan plan,
    DbPageRequest page,
    Integer pageSize
  ) {
    Integer offsetSize = page.offsetSize == null ? 0 : page.offsetSize;
    if (offsetSize < 0 || offsetSize > MAX_OFFSET) {
      throw new DbQueryException('Offset must be between 0 and ' + MAX_OFFSET);
    }
    if (page.afterId != null || page.afterValue != null) {
      throw new DbQueryException('OFFSET does not accept keyset continuation');
    }

    DbQueryService.requireRows(pageSize + 1);

    String soql = plan.toSoql() + ' LIMIT ' + plan.bindValue(pageSize + 1);
    if (offsetSize > 0) {
      soql += ' OFFSET ' + plan.bindValue(offsetSize);
    }

    DbQueryResult result = DbQueryService.queryPage(plan, soql, pageSize);
    result.strategy = DbPageRequest.OFFSET;
    if (result.hasNext && offsetSize + pageSize <= MAX_OFFSET) {
      result.nextOffset = offsetSize + pageSize;
    }

    return result;
  }
}
