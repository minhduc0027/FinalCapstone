public interface IDbPageStrategy {
  DbQueryResult execute(DbQueryPlan plan, DbPageRequest page, Integer pageSize);
}
