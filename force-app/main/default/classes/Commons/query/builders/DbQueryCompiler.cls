public with sharing class DbQueryCompiler {
  private static final Set<String> ORDERING_OPERATORS = new Set<String>{
    '>',
    '<',
    '>=',
    '<='
  };

  private static final Set<String> EQUALITY_OPERATORS = new Set<String>{
    '=',
    '!='
  };

  private static final Set<String> LIST_OPERATORS = new Set<String>{
    'IN',
    'NOT IN'
  };

  private static final String LIKE_OPERATOR = 'LIKE';

  private static final Set<String> OPERATORS = buildSupportedOperators();

  private static final Set<Schema.DisplayType> NUMERIC_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.INTEGER,
    Schema.DisplayType.DOUBLE,
    Schema.DisplayType.CURRENCY,
    Schema.DisplayType.PERCENT
  };

  private static final Set<Schema.DisplayType> DATE_TIME_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.DATE,
    Schema.DisplayType.DATETIME
  };

  private static final Set<Schema.DisplayType> STRING_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.STRING,
    Schema.DisplayType.TEXTAREA,
    Schema.DisplayType.PICKLIST,
    Schema.DisplayType.EMAIL,
    Schema.DisplayType.PHONE,
    Schema.DisplayType.URL,
    Schema.DisplayType.ENCRYPTEDSTRING
  };

  private static final Set<Schema.DisplayType> LIKE_SUPPORT_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.STRING,
    Schema.DisplayType.PICKLIST,
    Schema.DisplayType.EMAIL,
    Schema.DisplayType.PHONE
  };

  private static final Set<Schema.DisplayType> EQUALITY_SUPPORT_TYPES = buildEqualitySupportTypes();

  public static DbQueryPlan compile(DbQueryRequest request) {
    if (request == null) {
      throw new DbQueryException('Query request is required');
    }
    if (String.isBlank(request.objectName)) {
      throw new DbQueryException('Object name is required');
    }
    if (request.fields == null || request.fields.isEmpty()) {
      throw new DbQueryException('At least one SELECT field is required');
    }

    Schema.SObjectType objectType = SchemaHelper.getSObjectType(
      request.objectName
    );
    String objectName = objectType.getDescribe().getName();

    List<String> selectFields = new List<String>();
    Set<String> seen = new Set<String>();
    for (String field : request.fields) {
      String normalized = SchemaHelper.normalizeFieldPath(objectName, field);
      if (!seen.add(normalized.toLowerCase())) {
        throw new DbQueryException('Duplicate selected field: ' + field);
      }
      selectFields.add(normalized);
    }

    Map<String, Object> binds = new Map<String, Object>();
    List<String> whereParts = new List<String>();
    Integer bindIndex = 0;
    List<FilterCondition> filters = request.filters == null
      ? new List<FilterCondition>()
      : request.filters;
    for (FilterCondition condition : filters) {
      if (condition == null) {
        throw new DbQueryException('Filter cannot be null');
      }

      Schema.DescribeFieldResult fieldDescribe = SchemaHelper.resolveFieldPath(
        objectName,
        condition.field
      );
      if (!fieldDescribe.isFilterable()) {
        throw new DbQueryException(
          'Field is not filterable: ' + condition.field
        );
      }

      String operator = condition.operator == null
        ? ''
        : condition.operator.trim().toUpperCase();
      if (!OPERATORS.contains(operator)) {
        throw new DbQueryException(
          'Unsupported operator for ' +
            condition.field +
            ': ' +
            condition.operator
        );
      }

      validateOperator(condition.field, operator, fieldDescribe.getType());
      String bindName = 'b' + bindIndex++;
      whereParts.add(
        SchemaHelper.normalizeFieldPath(objectName, condition.field) +
          ' ' +
          operator +
          ' :' +
          bindName
      );
      binds.put(
        bindName,
        coerceValue(
          condition.value,
          fieldDescribe.getType(),
          condition.field,
          operator
        )
      );
    }

    String orderField = String.isBlank(request.orderBy)
      ? 'Id'
      : SchemaHelper.normalizeFieldPath(objectName, request.orderBy);
    if (!SchemaHelper.isSortable(objectName, orderField)) {
      throw new DbQueryException('Field is not sortable: ' + orderField);
    }

    if (
      request.page != null &&
      request.page.strategy != null &&
      request.page.strategy.trim().equalsIgnoreCase(DbPageRequest.KEYSET)
    ) {
      if (seen.add(orderField.toLowerCase())) {
        selectFields.add(orderField);
      }
      if (seen.add('id')) {
        selectFields.add('Id');
      }
    }

    DbQueryPlan plan = new DbQueryPlan();
    plan.objectName = objectName;
    plan.selectFrom =
      'SELECT ' +
      String.join(selectFields, ', ') +
      ' FROM ' +
      objectName;
    plan.whereParts = whereParts;
    plan.binds = binds;
    plan.orderField = orderField;
    plan.descending = request.orderDesc == true;
    return plan;
  }

  private static void validateOperator(
    String path,
    String operator,
    Schema.DisplayType type
  ) {
    if (operator == LIKE_OPERATOR && !LIKE_SUPPORT_TYPES.contains(type)) {
      throw new DbQueryException(
        'LIKE is not supported for field ' + path + ' (' + type + ')'
      );
    }

    if (
      ORDERING_OPERATORS.contains(operator) &&
      !(NUMERIC_TYPES.contains(type) || DATE_TIME_TYPES.contains(type))
    ) {
      throw new DbQueryException(
        'Comparison operator ' +
          operator +
          ' is not supported for field ' +
          path +
          ' (' +
          type +
          ')'
      );
    }

    if (
      EQUALITY_OPERATORS.contains(operator) &&
      !EQUALITY_SUPPORT_TYPES.contains(type)
    ) {
      throw new DbQueryException(
        'Equality operator ' +
          operator +
          ' is not supported for field ' +
          path +
          ' (' +
          type +
          ')'
      );
    }
  }

  private static Object coerceValue(
    Object value,
    Schema.DisplayType type,
    String path,
    String operator
  ) {
    if (value == null) {
      if (EQUALITY_OPERATORS.contains(operator)) {
        return null;
      }

      throw new DbQueryException(
        operator + ' does not support a null value for ' + path
      );
    }

    if (LIST_OPERATORS.contains(operator)) {
      if (!(value instanceof List<Object>)) {
        throw new DbQueryException(
          operator + ' requires a list value for ' + path
        );
      }

      return coerceList((List<Object>) value, type, path, operator);
    }

    return coerceFieldValue(value, type, path);
  }

  private static Object coerceList(
    List<Object> values,
    Schema.DisplayType type,
    String path,
    String operator
  ) {
    if (values.isEmpty()) {
      throw new DbQueryException(
        operator + ' requires at least one value for ' + path
      );
    }

    if (STRING_TYPES.contains(type)) {
      Set<String> converted = new Set<String>();

      for (Object item : values) {
        converted.add((String) coerceFieldValue(item, type, path));
      }

      return converted;
    }

    if (type == Schema.DisplayType.INTEGER) {
      Set<Integer> converted = new Set<Integer>();
      for (Object item : values) {
        converted.add((Integer) coerceFieldValue(item, type, path));
      }
      return converted;
    }

    if (NUMERIC_TYPES.contains(type)) {
      Set<Decimal> converted = new Set<Decimal>();

      for (Object item : values) {
        converted.add((Decimal) coerceFieldValue(item, type, path));
      }

      return converted;
    }

    if (type == Schema.DisplayType.DATE) {
      Set<Date> converted = new Set<Date>();

      for (Object item : values) {
        converted.add((Date) coerceFieldValue(item, type, path));
      }

      return converted;
    }

    if (type == Schema.DisplayType.DATETIME) {
      Set<Datetime> converted = new Set<Datetime>();

      for (Object item : values) {
        converted.add((Datetime) coerceFieldValue(item, type, path));
      }

      return converted;
    }

    if (type == Schema.DisplayType.ID || type == Schema.DisplayType.REFERENCE) {
      Set<Id> converted = new Set<Id>();

      for (Object item : values) {
        converted.add((Id) coerceFieldValue(item, type, path));
      }

      return converted;
    }

    if (type == Schema.DisplayType.BOOLEAN) {
      Set<Boolean> converted = new Set<Boolean>();

      for (Object item : values) {
        converted.add((Boolean) coerceFieldValue(item, type, path));
      }

      return converted;
    }

    throw new DbQueryException(
      operator + ' is not supported for field ' + path + ' (' + type + ')'
    );
  }

  /**
   * Converts a scalar boundary/filter value to the described field type.
   * @param value Native Apex value or a scalar from a JSON request
   * @param type Described Salesforce field type
   * @param path Field path used in conversion errors
   * @return A typed SOQL bind value, preserving null
   * @throws DbQueryException when conversion is not possible
   */
  public static Object coerceFieldValue(
    Object value,
    Schema.DisplayType type,
    String path
  ) {
    if (value == null) {
      return null;
    }

    try {
      if (type == Schema.DisplayType.DATE) {
        return value instanceof Date
          ? value
          : Date.valueOf(String.valueOf(value));
      }

      if (type == Schema.DisplayType.DATETIME) {
        if (value instanceof Datetime) {
          return value;
        }
        String text = String.valueOf(value);
        return text.contains('T')
          ? (Datetime) JSON.deserialize(JSON.serialize(text), Datetime.class)
          : Datetime.valueOf(text);
      }
      if (type == Schema.DisplayType.TIME) {
        return value instanceof Time
          ? value
          : (Time) JSON.deserialize(JSON.serialize(value), Time.class);
      }

      if (NUMERIC_TYPES.contains(type)) {
        Decimal numberValue = Decimal.valueOf(String.valueOf(value));
        if (type == Schema.DisplayType.INTEGER) {
          Integer integerValue = numberValue.intValue();
          if (numberValue != integerValue) {
            throw new DbQueryException(
              'Expected a whole integer for field ' + path
            );
          }
          return integerValue;
        }
        return numberValue;
      }

      if (type == Schema.DisplayType.BOOLEAN) {
        if (value instanceof Boolean) {
          return value;
        }
        String boolValue = String.valueOf(value).trim().toLowerCase();
        if (boolValue != 'true' && boolValue != 'false') {
          throw new DbQueryException('Expected true/false');
        }
        return boolValue == 'true';
      }

      if (
        type == Schema.DisplayType.ID ||
        type == Schema.DisplayType.REFERENCE
      ) {
        if (value instanceof Id) {
          return value;
        }
        return Id.valueOf(String.valueOf(value));
      }

      if (STRING_TYPES.contains(type)) {
        return String.valueOf(value);
      }

      throw new DbQueryException(
        'Unsupported field type for ' + path + ': ' + String.valueOf(type)
      );
    } catch (DbQueryException cre) {
      throw cre;
    } catch (Exception e) {
      throw new DbQueryException(
        'Invalid value for field ' +
          path +
          ' (' +
          type +
          '): ' +
          String.valueOf(value)
      );
    }
  }

  private static Set<String> buildSupportedOperators() {
    Set<String> operators = new Set<String>();
    operators.addAll(ORDERING_OPERATORS);
    operators.addAll(EQUALITY_OPERATORS);
    operators.addAll(LIST_OPERATORS);
    operators.add(LIKE_OPERATOR);
    return operators;
  }

  private static Set<Schema.DisplayType> buildEqualitySupportTypes() {
    Set<Schema.DisplayType> types = new Set<Schema.DisplayType>();

    types.addAll(STRING_TYPES);
    types.addAll(NUMERIC_TYPES);
    types.addAll(DATE_TIME_TYPES);

    types.add(Schema.DisplayType.BOOLEAN);
    types.add(Schema.DisplayType.REFERENCE);
    types.add(Schema.DisplayType.ID);

    return types;
  }
}
