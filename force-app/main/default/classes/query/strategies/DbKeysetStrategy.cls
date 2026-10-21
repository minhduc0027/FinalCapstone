/**
 * Seeks by (ordered field, Id), following Salesforce's native null ordering.
 * Continuation values are caller-owned boundaries, not authorization tokens.
 */
public with sharing class DbKeysetStrategy implements IDbPageStrategy {
  /**
   * Executes one page with a bound lexicographic continuation predicate.
   * @param plan Validated compiler output, including the ordered field projection
   * @param page afterId and afterValue from the previous page
   * @param pageSize Effective server-capped page size
   * @return Page records and the last (value, Id) when another page exists
   * @throws DbQueryException for unsupported ordering or invalid continuation
   */
  public DbQueryResult execute(
    DbQueryPlan plan,
    DbPageRequest page,
    Integer pageSize
  ) {
    Schema.DescribeFieldResult field = SchemaHelper.resolveFieldPath(
      plan.objectName,
      plan.orderField
    );
    validateOrder(field, plan.orderField);

    if (page.offsetSize != null && page.offsetSize != 0) {
      throw new DbQueryException('KEYSET does not accept offsetSize');
    }
    if (page.afterId == null && page.afterValue != null) {
      throw new DbQueryException('KEYSET afterValue requires afterId');
    }

    Boolean idOrder = plan.orderField.equalsIgnoreCase('Id');
    if (idOrder && page.afterValue != null) {
      throw new DbQueryException('Id ordering uses afterId only');
    }

    Integer querySize = pageSize + 1;
    DbQueryService.requireRows(querySize);
    if (page.afterId != null) {
      plan.whereParts.add(continuation(plan, page, field.getType(), idOrder));
    }

    String soql = plan.toSoql() + ' LIMIT ' + plan.bindValue(querySize);
    DbQueryResult result = DbQueryService.queryPage(plan, soql, pageSize);
    result.strategy = DbPageRequest.KEYSET;
    if (result.hasNext) {
      SObject last = result.records[result.records.size() - 1];
      result.nextAfterId = last.Id;
      if (!idOrder) {
        result.nextAfterValue = readPath(last, plan.orderField);
      }
    }

    return result;
  }

  private static void validateOrder(
    Schema.DescribeFieldResult field,
    String path
  ) {
    if (!field.isSortable() || !field.isFilterable()) {
      throw new DbQueryException(
        'KEYSET requires a sortable, filterable field: ' + path
      );
    }

    if (field.getType() == Schema.DisplayType.PICKLIST) {
      throw new DbQueryException(
        'KEYSET cannot seek configured picklist order: ' +
          path +
          '. Use OFFSET or PAGE_CURSOR.'
      );
    }
  }

  private static String continuation(
    DbQueryPlan plan,
    DbPageRequest page,
    Schema.DisplayType type,
    Boolean idOrder
  ) {
    String comparison = plan.descending ? '<' : '>';
    String idBoundary = 'Id ' + comparison + ' ' + plan.bindValue(page.afterId);
    if (idOrder) {
      return idBoundary;
    }

    String field = plan.orderField;
    Object value = DbQueryCompiler.coerceFieldValue(
      page.afterValue,
      type,
      field
    );

    String bound = plan.bindValue(value);
    String tied = '(' + field + ' = ' + bound + ' AND ' + idBoundary + ')';
    // Lookup Ids follow Id ordering: nulls trail a descending reference sort.
    Boolean nullsFirst = !(type == Schema.DisplayType.REFERENCE &&
    plan.descending);
    if (value == null) {
      return nullsFirst
        ? '(' + tied + ' OR ' + field + ' != ' + bound + ')'
        : tied;
    }

    if (type == Schema.DisplayType.BOOLEAN) {
      Boolean later = plan.descending ? false : true;
      return (Boolean) value == later
        ? tied
        : '(' + tied + ' OR ' + field + ' = ' + plan.bindValue(later) + ')';
    }

    String nullTail = nullsFirst ? '' : ' OR ' + field + ' = null';
    return '(' +
      tied +
      ' OR (' +
      field +
      ' != null AND ' +
      field +
      ' ' +
      comparison +
      ' ' +
      bound +
      ')' +
      nullTail +
      ')';
  }

  private static Object readPath(SObject record, String path) {
    List<String> segments = path.split('\\.');
    for (Integer i = 0; i < segments.size() - 1; i++) {
      record = record.getSObject(segments[i]);
      if (record == null) {
        return null;
      }
    }

    return record.get(segments[segments.size() - 1]);
  }
}
