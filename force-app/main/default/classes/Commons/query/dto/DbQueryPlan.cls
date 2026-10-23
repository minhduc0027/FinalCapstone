public with sharing class DbQueryPlan {
  public String objectName;
  public String selectFrom;
  public List<String> whereParts;
  public Map<String, Object> binds;
  public String orderField;
  public Boolean descending;

  public DbQueryPlan() {
    whereParts = new List<String>();
    binds = new Map<String, Object>();
    orderField = 'Id';
    descending = false;
  }

  public String toSoql() {
    if (String.isBlank(selectFrom)) {
      throw new DbQueryException('Query selectFrom is required');
    }

    String soql = selectFrom;

    if (!whereParts.isEmpty()) {
      soql += ' WHERE ' + String.join(whereParts, ' AND ');
    }

    String direction = descending ? ' DESC' : ' ASC';
    soql += ' ORDER BY ' + orderField + direction;

    if (!orderField.equalsIgnoreCase('Id')) {
      soql += ', Id' + direction;
    }

    return soql;
  }

  public String bindValue(Object value) {
    String name = 'b' + binds.size();
    binds.put(name, value);
    return ':' + name;
  }
}
