public with sharing class GenericSelector {

    private static final Integer DEFAULT_LIMIT = 100;
    private static final Integer MAX_SELECT_FIELDS = 30;
    private static final Set<String> ALLOWED_OPERATORS =
        new Set<String>{
            '=', '!=', '>', '<', '>=', '<=', 'LIKE', 'IN', 'NOT IN'
        };

    private static final Set<Schema.DisplayType> LIKE_TYPES =
        new Set<Schema.DisplayType>{
            Schema.DisplayType.STRING,
            Schema.DisplayType.PICKLIST,
            Schema.DisplayType.EMAIL,
            Schema.DisplayType.PHONE,
            Schema.DisplayType.URL
        };

    private static final Set<Schema.DisplayType> COMPARISON_TYPES =
        new Set<Schema.DisplayType>{
            Schema.DisplayType.INTEGER,
            Schema.DisplayType.DOUBLE,
            Schema.DisplayType.CURRENCY,
            Schema.DisplayType.PERCENT,
            Schema.DisplayType.DATE,
            Schema.DisplayType.DATETIME,
            Schema.DisplayType.ID,
            Schema.DisplayType.REFERENCE
        };

    private static final Set<Schema.DisplayType> KEYSET_TYPES =
        new Set<Schema.DisplayType>{
            Schema.DisplayType.INTEGER,
            Schema.DisplayType.DOUBLE,
            Schema.DisplayType.CURRENCY,
            Schema.DisplayType.PERCENT,
            Schema.DisplayType.DATE,
            Schema.DisplayType.DATETIME,
            Schema.DisplayType.STRING,
            Schema.DisplayType.ID,
            Schema.DisplayType.REFERENCE,
            Schema.DisplayType.EMAIL,
            Schema.DisplayType.PHONE
        };


    /*
    * Count records matching the supplied filters.
    *
    * SELECT fields, ORDER BY, LIMIT and keyset cursor
    * are not used for count queries.
    */
    public static Integer countRecords(ReportRequest request) {
        validateCountRequest(request);
        Schema.SObjectType objectType =
            SchemaHelper.getSObjectType(
                request.objectName
            );

        String canonicalObjectName =
            objectType
                .getDescribe()
                .getName();

        Map<String, Object> binds =
            new Map<String, Object>();

        List<String> whereConditions =
            buildWhereConditions(
                canonicalObjectName,
                request.filters,
                binds
            );

        String soql =
            'SELECT COUNT() FROM ' +
            canonicalObjectName;

        if (!whereConditions.isEmpty()) {
            soql +=
                ' WHERE ' +
                String.join(
                    whereConditions,
                    ' AND '
                );
        }

        try {
            return Database.countQueryWithBinds(
                soql,
                binds,
                AccessLevel.SYSTEM_MODE
            );
        } catch (QueryException ex) {
            throw new ConfigReportException(
                'Unable to count records for object "' +
                canonicalObjectName +
                '": ' +
                sanitizeQueryException(
                    ex.getMessage()
                )
            );
        }
    }
    
    /*
     * Main query entry point.
     */
    public static ReportResult selectRecords(
        ReportRequest request,
        Integer maxRows
    ) {
        validateRequest(request);

        Integer normalizedMaxRows =
            normalizeMaxRows(maxRows);

        Integer requestedLimit =
            normalizeRequestedLimit(
                request.limitSize
            );

        Integer effectiveLimit =
            Math.min(
                requestedLimit,
                normalizedMaxRows
            );

        Boolean wasCapped =
            requestedLimit > normalizedMaxRows;

        Schema.SObjectType objectType =
            SchemaHelper.getSObjectType(
                request.objectName
            );

        String canonicalObjectName =
            objectType
                .getDescribe()
                .getName();

        List<String> validatedSelectFields =
            validateSelectFields(
                canonicalObjectName,
                request.fields
            );

        /*
         * Id is required as the deterministic keyset
         * tie-breaker.
         */
        ensureRequiredCursorFields(
            validatedSelectFields,
            request.keysetCursor
        );

        Map<String, Object> binds =
            new Map<String, Object>();

        List<String> whereConditions =
            buildWhereConditions(
                canonicalObjectName,
                request.filters,
                binds
            );

        /*
         * Keyset condition is added after standard filters.
         */
        addKeysetCondition(
            canonicalObjectName,
            request.keysetCursor,
            whereConditions,
            binds
        );

        List<String> normalizedOrderFields =
            normalizeOrderByFields(request);

        validateKeysetOrdering(
            request.keysetCursor,
            normalizedOrderFields,
            request.orderDesc
        );

        String orderByClause =
            buildOrderByClause(
                canonicalObjectName,
                normalizedOrderFields,
                request.orderDesc
            );

        /*
         * LIMIT is also bound rather than concatenating
         * the runtime value into the SOQL string.
         */
        binds.put(
            'limitSize',
            effectiveLimit
        );

        String soql =
            'SELECT ' +
            String.join(
                validatedSelectFields,
                ', '
            ) +
            ' FROM ' +
            canonicalObjectName;

        if (!whereConditions.isEmpty()) {
            soql +=
                ' WHERE ' +
                String.join(
                    whereConditions,
                    ' AND '
                );
        }

        soql += orderByClause;
        soql += ' LIMIT :limitSize';

        List<SObject> records;

        try {
            records = Database.queryWithBinds(
                soql,
                binds,
                AccessLevel.USER_MODE
                //AccessLevel.SYSTEM_MODE // Bypass FLS, Object Permission (CRUD), Sharing Rules,...
            );
        } catch (QueryException ex) {
            throw new ConfigReportException(
                'Unable to execute report for object "' +
                canonicalObjectName +
                '": ' +
                sanitizeQueryException(
                    ex.getMessage()
                )
            );
        }

        ReportResult result =
            new ReportResult();

        result.records = records;
        result.soql = soql;
        result.bindCount = binds.size();
        result.truncated = wasCapped;

        return result;
    }

    /*
     * Validate primary request structure.
     */
    private static void validateRequest(
        ReportRequest request
    ) {
        if (request == null) {
            throw new ConfigReportException(
                'Report request must not be null.'
            );
        }

        if (String.isBlank(request.objectName)) {
            throw new ConfigReportException(
                'Report object name must not be blank.'
            );
        }

        if (
            request.fields == null ||
            request.fields.isEmpty()
        ) {
            throw new ConfigReportException(
                'At least one SELECT field is required.'
            );
        }

        if (
            request.fields.size() >
            MAX_SELECT_FIELDS
        ) {
            throw new ConfigReportException(
                'A report cannot contain more than ' +
                MAX_SELECT_FIELDS +
                ' fields.'
            );
        }

        validateRawCursor(request.keysetCursor);
    }

    /*
     * Validate cursor before schema validation.
     */
    private static void validateRawCursor(
        KeysetCursor cursor
    ) {
        if (cursor == null) {
            return;
        }

        if (String.isBlank(cursor.primaryField)) {
            throw new ConfigReportException(
                'Keyset cursor primary field must not be blank.'
            );
        }

        if (cursor.primaryValue == null) {
            throw new ConfigReportException(
                'Keyset cursor primary value must not be null.'
            );
        }

        if (cursor.recordId == null) {
            throw new ConfigReportException(
                'Keyset cursor record Id must not be null.'
            );
        }

        if (cursor.descending == null) {
            throw new ConfigReportException(
                'Keyset cursor direction must be provided.'
            );
        }
    }

    private static Integer normalizeMaxRows(
        Integer maxRows
    ) {
        if (
            maxRows == null ||
            maxRows <= 0
        ) {
            throw new ConfigReportException(
                'maxRows must be greater than zero.'
            );
        }

        return maxRows;
    }

    private static Integer normalizeRequestedLimit(
        Integer requestedLimit
    ) {
        if (
            requestedLimit == null ||
            requestedLimit <= 0
        ) {
            return DEFAULT_LIMIT;
        }

        return requestedLimit;
    }

    /*
     * Add the keyset condition:
     *
     * Descending:
     * CreatedDate < cursor
     * OR (
     *     CreatedDate = cursor
     *     AND Id < cursorId
     * )
     *
     * Ascending uses > instead.
     */
    private static void addKeysetCondition(
        String objectName,
        KeysetCursor cursor,
        List<String> whereConditions,
        Map<String, Object> queryBinds
    ) {
        if (cursor == null) {
            return;
        }

        String primaryField =
            normalizeRequiredValue(
                cursor.primaryField,
                'Keyset cursor primary field'
            );

        Schema.DescribeFieldResult fieldDescribe =
            SchemaHelper.resolveFieldPath(
                objectName,
                primaryField
            );

        if (!fieldDescribe.isFilterable()) {
            throw new ConfigReportException(
                'Keyset field "' +
                primaryField +
                '" is not filterable.'
            );
        }

        if (!fieldDescribe.isSortable()) {
            throw new ConfigReportException(
                'Keyset field "' +
                primaryField +
                '" is not sortable.'
            );
        }

        if (
            !KEYSET_TYPES.contains(
                fieldDescribe.getType()
            )
        ) {
            throw new ConfigReportException(
                'Field "' +
                primaryField +
                '" of type ' +
                String.valueOf(
                    fieldDescribe.getType()
                ) +
                ' cannot be used for keyset pagination.'
            );
        }

        Object convertedPrimaryValue =
            convertSingleValue(
                primaryField,
                cursor.primaryValue,
                fieldDescribe.getType()
            );

        String comparisonOperator =
            cursor.descending == true
                ? '<'
                : '>';

        queryBinds.put(
            'cursorPrimaryValue',
            convertedPrimaryValue
        );

        queryBinds.put(
            'cursorRecordId',
            cursor.recordId
        );

        whereConditions.add(
            '(' +
                primaryField +
                ' ' +
                comparisonOperator +
                ' :cursorPrimaryValue' +
                ' OR (' +
                    primaryField +
                    ' = :cursorPrimaryValue' +
                    ' AND Id ' +
                    comparisonOperator +
                    ' :cursorRecordId' +
                ')' +
            ')'
        );
    }

    /*
     * Ensure fields needed by the caller to create
     * the next cursor are included in SELECT.
     */
    private static void ensureRequiredCursorFields(
        List<String> selectedFields,
        KeysetCursor cursor
    ) {
        if (cursor == null) {
            return;
        }

        Set<String> normalizedSelectedFields =
            new Set<String>();

        for (String fieldName : selectedFields) {
            normalizedSelectedFields.add(
                fieldName.toLowerCase()
            );
        }

        if (
            !normalizedSelectedFields.contains(
                cursor.primaryField
                    .trim()
                    .toLowerCase()
            )
        ) {
            throw new ConfigReportException(
                'The keyset primary field "' +
                cursor.primaryField +
                '" must be included in SELECT fields.'
            );
        }

        if (
            !normalizedSelectedFields.contains('id')
        ) {
            throw new ConfigReportException(
                'Field "Id" must be included when using keyset pagination.'
            );
        }
    }

    /*
     * Support new orderByFields while preserving
     * backward compatibility with the old orderBy field.
     */
    private static List<String> normalizeOrderByFields(
        ReportRequest request
    ) {
        List<String> output =
            new List<String>();

        Set<String> uniquenessKeys =
            new Set<String>();

        if (
            request.orderByFields != null &&
            !request.orderByFields.isEmpty()
        ) {
            for (
                String orderField :
                request.orderByFields
            ) {
                String normalizedField =
                    normalizeRequiredValue(
                        orderField,
                        'ORDER BY field'
                    );

                String uniquenessKey =
                    normalizedField.toLowerCase();

                if (
                    uniquenessKeys.contains(
                        uniquenessKey
                    )
                ) {
                    throw new ConfigReportException(
                        'Duplicate ORDER BY field: "' +
                        normalizedField +
                        '".'
                    );
                }

                uniquenessKeys.add(
                    uniquenessKey
                );

                output.add(
                    normalizedField
                );
            }

            return output;
        }

        /*
         * Backward compatibility.
         */
        if (String.isNotBlank(request.orderBy)) {
            output.add(
                request.orderBy.trim()
            );
        }

        return output;
    }

    /*
     * For keyset pagination, sorting must match
     * the cursor exactly:
     *
     * ORDER BY primaryField direction, Id direction
     */
    private static void validateKeysetOrdering(
        KeysetCursor cursor,
        List<String> orderByFields,
        Boolean orderDesc
    ) {
        if (cursor == null) {
            return;
        }

        if (orderByFields == null) {
            throw new ConfigReportException(
                'ORDER BY fields are required for keyset pagination.'
            );
        }

        if (orderByFields.size() != 2) {
            throw new ConfigReportException(
                'Keyset pagination requires exactly two ORDER BY fields: ' +
                'the cursor primary field and Id.'
            );
        }

        String expectedPrimaryField =
            cursor.primaryField
                .trim()
                .toLowerCase();

        String actualPrimaryField =
            orderByFields[0]
                .trim()
                .toLowerCase();

        String actualTieBreaker =
            orderByFields[1]
                .trim()
                .toLowerCase();

        if (
            expectedPrimaryField !=
            actualPrimaryField
        ) {
            throw new ConfigReportException(
                'The first ORDER BY field must match the keyset primary field "' +
                cursor.primaryField +
                '".'
            );
        }

        if (actualTieBreaker != 'id') {
            throw new ConfigReportException(
                'The second ORDER BY field must be Id for deterministic keyset pagination.'
            );
        }

        Boolean normalizedOrderDesc =
            orderDesc == true;

        if (
            cursor.descending !=
            normalizedOrderDesc
        ) {
            throw new ConfigReportException(
                'Keyset cursor direction must match the ORDER BY direction.'
            );
        }
    }

    private static List<String> validateSelectFields(
        String objectName,
        List<String> requestedFields
    ) {
        List<String> validatedFields =
            new List<String>();

        Set<String> uniqueFields =
            new Set<String>();

        for (String fieldPath : requestedFields) {
            if (String.isBlank(fieldPath)) {
                throw new ConfigReportException(
                    'SELECT field must not be blank.'
                );
            }

            String normalizedPath =
                fieldPath.trim();

            SchemaHelper.resolveFieldPath(
                objectName,
                normalizedPath
            );

            String uniquenessKey =
                normalizedPath.toLowerCase();

            if (
                uniqueFields.contains(
                    uniquenessKey
                )
            ) {
                throw new ConfigReportException(
                    'Duplicate SELECT field: "' +
                    normalizedPath +
                    '".'
                );
            }

            uniqueFields.add(
                uniquenessKey
            );

            validatedFields.add(
                normalizedPath
            );
        }

        return validatedFields;
    }

    private static List<String> buildWhereConditions(
        String objectName,
        List<FilterCondition> filters,
        Map<String, Object> binds
    ) {
        List<String> whereConditions =
            new List<String>();

        if (
            filters == null ||
            filters.isEmpty()
        ) {
            return whereConditions;
        }

        for (
            Integer index = 0;
            index < filters.size();
            index++
        ) {
            FilterCondition condition =
                filters[index];

            if (condition == null) {
                throw new ConfigReportException(
                    'Filter at index ' +
                    index +
                    ' must not be null.'
                );
            }

            String fieldPath =
                normalizeRequiredValue(
                    condition.field,
                    'Filter field at index ' +
                    index
                );

            String operatorValue =
                normalizeOperator(
                    condition.operator,
                    index
                );

            Schema.DescribeFieldResult fieldDescribe =
                SchemaHelper.resolveFieldPath(
                    objectName,
                    fieldPath
                );

            if (!fieldDescribe.isFilterable()) {
                throw new ConfigReportException(
                    'Field "' +
                    fieldPath +
                    '" is not filterable.'
                );
            }

            validateOperatorForType(
                fieldPath,
                operatorValue,
                fieldDescribe.getType()
            );

            String bindName =
                'b' + index;

            Object convertedValue =
                convertFilterValue(
                    fieldPath,
                    operatorValue,
                    condition.value,
                    fieldDescribe.getType()
                );

            binds.put(
                bindName,
                convertedValue
            );

            whereConditions.add(
                fieldPath +
                ' ' +
                operatorValue +
                ' :' +
                bindName
            );
        }

        return whereConditions;
    }

    private static String buildOrderByClause(
        String objectName,
        List<String> orderByFields,
        Boolean orderDesc
    ) {
        if (
            orderByFields == null ||
            orderByFields.isEmpty()
        ) {
            return '';
        }

        String direction =
            orderDesc == true
                ? ' DESC'
                : ' ASC';

        List<String> orderByParts =
            new List<String>();

        Set<String> uniquenessKeys =
            new Set<String>();

        for (
            String fieldPath :
            orderByFields
        ) {
            String normalizedField =
                normalizeRequiredValue(
                    fieldPath,
                    'ORDER BY field'
                );

            String uniquenessKey =
                normalizedField.toLowerCase();

            if (
                uniquenessKeys.contains(
                    uniquenessKey
                )
            ) {
                throw new ConfigReportException(
                    'Duplicate ORDER BY field: "' +
                    normalizedField +
                    '".'
                );
            }

            Schema.DescribeFieldResult fieldDescribe =
                SchemaHelper.resolveFieldPath(
                    objectName,
                    normalizedField
                );

            if (!fieldDescribe.isSortable()) {
                throw new ConfigReportException(
                    'Field "' +
                    normalizedField +
                    '" is not sortable.'
                );
            }

            uniquenessKeys.add(
                uniquenessKey
            );

            orderByParts.add(
                normalizedField +
                direction
            );
        }

        return
            ' ORDER BY ' +
            String.join(
                orderByParts,
                ', '
            );
    }

    private static String normalizeOperator(
        String inputOperator,
        Integer filterIndex
    ) {
        if (String.isBlank(inputOperator)) {
            throw new ConfigReportException(
                'Operator is required for filter at index ' +
                filterIndex +
                '.'
            );
        }

        String normalizedOperator =
            inputOperator
                .trim()
                .toUpperCase()
                .replaceAll(
                    '\\s+',
                    ' '
                );

        if (
            !ALLOWED_OPERATORS.contains(
                normalizedOperator
            )
        ) {
            throw new ConfigReportException(
                'Unsupported operator "' +
                inputOperator +
                '" at filter index ' +
                filterIndex +
                '.'
            );
        }

        return normalizedOperator;
    }

    private static void validateOperatorForType(
        String fieldPath,
        String operatorValue,
        Schema.DisplayType fieldType
    ) {
        if (
            operatorValue == 'LIKE' &&
            !LIKE_TYPES.contains(fieldType)
        ) {
            throw new ConfigReportException(
                'Operator LIKE cannot be used with field "' +
                fieldPath +
                '" of type ' +
                String.valueOf(fieldType) +
                '.'
            );
        }

        if (
            (
                operatorValue == '>' ||
                operatorValue == '<' ||
                operatorValue == '>=' ||
                operatorValue == '<='
            ) &&
            !COMPARISON_TYPES.contains(fieldType)
        ) {
            throw new ConfigReportException(
                'Operator "' +
                operatorValue +
                '" cannot be used with field "' +
                fieldPath +
                '" of type ' +
                String.valueOf(fieldType) +
                '.'
            );
        }
    }

    private static Object convertCollectionValues(
        String fieldPath,
        List<Object> rawValues,
        Schema.DisplayType fieldType
    ) {
        /*
        * Id and reference fields must use a strongly typed
        * Id collection. List<Object> would be treated as ANY
        * by the dynamic SOQL bind engine.
        */
        if (
            fieldType == Schema.DisplayType.ID ||
            fieldType == Schema.DisplayType.REFERENCE
        ) {
            Set<Id> convertedValues = new Set<Id>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (Id) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        if (
            fieldType == Schema.DisplayType.STRING ||
            fieldType == Schema.DisplayType.TEXTAREA ||
            fieldType == Schema.DisplayType.PICKLIST ||
            fieldType == Schema.DisplayType.MULTIPICKLIST ||
            fieldType == Schema.DisplayType.EMAIL ||
            fieldType == Schema.DisplayType.PHONE ||
            fieldType == Schema.DisplayType.URL ||
            fieldType == Schema.DisplayType.ENCRYPTEDSTRING
        ) {
            List<String> convertedValues =
                new List<String>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (String) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        if (fieldType == Schema.DisplayType.BOOLEAN) {
            List<Boolean> convertedValues =
                new List<Boolean>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (Boolean) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        if (fieldType == Schema.DisplayType.DATE) {
            List<Date> convertedValues =
                new List<Date>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (Date) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        if (fieldType == Schema.DisplayType.DATETIME) {
            List<Datetime> convertedValues =
                new List<Datetime>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (Datetime) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        if (fieldType == Schema.DisplayType.INTEGER) {
            List<Integer> convertedValues =
                new List<Integer>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (Integer) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        if (
            fieldType == Schema.DisplayType.DOUBLE ||
            fieldType == Schema.DisplayType.CURRENCY ||
            fieldType == Schema.DisplayType.PERCENT
        ) {
            List<Decimal> convertedValues =
                new List<Decimal>();

            for (Object rawValue : rawValues) {
                convertedValues.add(
                    (Decimal) convertSingleValue(
                        fieldPath,
                        rawValue,
                        fieldType
                    )
                );
            }

            return convertedValues;
        }

        throw new ConfigReportException(
            'Field "' +
            fieldPath +
            '" has unsupported collection filter type ' +
            String.valueOf(fieldType) +
            '.'
        );
    }

    private static Object convertFilterValue(
        String fieldPath,
        String operatorValue,
        Object rawValue,
        Schema.DisplayType fieldType
    ) {
        if (
            operatorValue != 'IN' &&
            operatorValue != 'NOT IN'
        ) {
            return convertSingleValue(
                fieldPath,
                rawValue,
                fieldType
            );
        }

        List<Object> rawValues =
            normalizeCollectionValue(
                fieldPath,
                operatorValue,
                rawValue
            );

        return convertCollectionValues(
            fieldPath,
            rawValues,
            fieldType
        );
    }

    /*
     * @AuraEnabled input collections can arrive as
     * List<Object>, List<String>, Set<Id>, and so on.
     *
     * JSON serialization provides a generic, safe way to
     * normalize the supplied collection to List<Object>.
     */
    private static List<Object> normalizeCollectionValue(
        String fieldPath,
        String operatorValue,
        Object rawValue
    ) {
        if (rawValue == null) {
            throw new ConfigReportException(
                'Operator "' +
                operatorValue +
                '" requires a non-null collection for field "' +
                fieldPath +
                '".'
            );
        }

        List<Object> rawValues;

        try {
            rawValues =
                (List<Object>) JSON.deserializeUntyped(
                    JSON.serialize(rawValue)
                );
        } catch (Exception ex) {
            throw new ConfigReportException(
                'Operator "' +
                operatorValue +
                '" requires a list or set value for field "' +
                fieldPath +
                '".'
            );
        }

        if (
            rawValues == null ||
            rawValues.isEmpty()
        ) {
            throw new ConfigReportException(
                'Operator "' +
                operatorValue +
                '" requires a non-empty collection for field "' +
                fieldPath +
                '".'
            );
        }

        return rawValues;
    }

    private static Object convertSingleValue(
        String fieldPath,
        Object rawValue,
        Schema.DisplayType fieldType
    ) {
        if (rawValue == null) {
            return null;
        }

        try {
            if (
                fieldType == Schema.DisplayType.STRING ||
                fieldType == Schema.DisplayType.TEXTAREA ||
                fieldType == Schema.DisplayType.PICKLIST ||
                fieldType == Schema.DisplayType.MULTIPICKLIST ||
                fieldType == Schema.DisplayType.EMAIL ||
                fieldType == Schema.DisplayType.PHONE ||
                fieldType == Schema.DisplayType.URL ||
                fieldType == Schema.DisplayType.ENCRYPTEDSTRING
            ) {
                return String.valueOf(rawValue);
            }

            if (
                fieldType ==
                Schema.DisplayType.BOOLEAN
            ) {
                if (rawValue instanceof Boolean) {
                    return rawValue;
                }

                String booleanValue =
                    String.valueOf(rawValue)
                        .trim()
                        .toLowerCase();

                if (
                    booleanValue != 'true' &&
                    booleanValue != 'false'
                ) {
                    throw new ConfigReportException(
                        'Invalid Boolean value.'
                    );
                }

                return Boolean.valueOf(
                    booleanValue
                );
            }

            if (
                fieldType ==
                Schema.DisplayType.DATE
            ) {
                if (rawValue instanceof Date) {
                    return rawValue;
                }

                return Date.valueOf(
                    String.valueOf(rawValue)
                );
            }

            if (
                fieldType ==
                Schema.DisplayType.DATETIME
            ) {
                if (
                    rawValue instanceof Datetime
                ) {
                    return rawValue;
                }

                return parseDatetimeValue(
                    String.valueOf(rawValue)
                );
            }

            if (
                fieldType ==
                Schema.DisplayType.INTEGER
            ) {
                if (
                    rawValue instanceof Integer
                ) {
                    return rawValue;
                }

                return Integer.valueOf(
                    String.valueOf(rawValue)
                );
            }

            if (
                fieldType ==
                    Schema.DisplayType.DOUBLE ||
                fieldType ==
                    Schema.DisplayType.CURRENCY ||
                fieldType ==
                    Schema.DisplayType.PERCENT
            ) {
                if (
                    rawValue instanceof Decimal
                ) {
                    return rawValue;
                }

                return Decimal.valueOf(
                    String.valueOf(rawValue)
                );
            }

            if (
                fieldType ==
                    Schema.DisplayType.ID ||
                fieldType ==
                    Schema.DisplayType.REFERENCE
            ) {
                String idValue =
                    String.valueOf(rawValue)
                        .trim();

                try {
                    return Id.valueOf(idValue);
                } catch (Exception ex) {
                    throw new ConfigReportException(
                        'Invalid Salesforce Id value.'
                    );
                }
            }

            throw new ConfigReportException(
                'Field "' +
                fieldPath +
                '" has unsupported filter type ' +
                String.valueOf(fieldType) +
                '.'
            );
        } catch (ConfigReportException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ConfigReportException(
                'Invalid value "' +
                String.valueOf(rawValue) +
                '" for field "' +
                fieldPath +
                '" of type ' +
                String.valueOf(fieldType) +
                '.'
            );
        }
    }

    /*
     * Supports:
     *
     * 2026-10-12 08:30:00
     * 2026-10-12T08:30:00
     * 2026-10-12T08:30:00Z
     * 2026-10-12T08:30:00.000Z
     */
    private static Datetime parseDatetimeValue(
        String rawValue
    ) {
        String normalizedValue =
            rawValue.trim();

        Boolean isUtcValue =
            normalizedValue.endsWith('Z');

        normalizedValue =
            normalizedValue
                .replace('T', ' ')
                .replace('Z', '');

        Integer decimalIndex =
            normalizedValue.indexOf('.');

        if (decimalIndex >= 0) {
            normalizedValue =
                normalizedValue.substring(
                    0,
                    decimalIndex
                );
        }

        if (isUtcValue) {
            return Datetime.valueOfGmt(
                normalizedValue
            );
        }

        return Datetime.valueOf(
            normalizedValue
        );
    }

    private static String normalizeRequiredValue(
        String value,
        String label
    ) {
        if (String.isBlank(value)) {
            throw new ConfigReportException(
                label +
                ' must not be blank.'
            );
        }

        return value.trim();
    }

    private static String sanitizeQueryException(
        String message
    ) {
        if (String.isBlank(message)) {
            return 'Query failed.';
        }

        /*
         * Do not append the complete SOQL statement.
         * QueryException may already contain the necessary
         * field or access information.
         */
        return message;
    }

    private static void validateCountRequest(ReportRequest request) {
        if (request == null) {
            throw new ConfigReportException('Count request must not be null.');
        }
        if (String.isBlank(request.objectName)) {
            throw new ConfigReportException('Count object name must not be blank.');
        }
    }
}