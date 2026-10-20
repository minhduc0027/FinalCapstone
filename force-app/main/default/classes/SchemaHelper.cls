public with sharing class SchemaHelper {

    private static Map<String, Schema.SObjectType> objectTypesByLowerName;

    private static Map<String, Set<String>> accessibleFieldCache =
        new Map<String, Set<String>>();

    private static Map<String, Schema.DescribeFieldResult> fieldPathCache =
        new Map<String, Schema.DescribeFieldResult>();

    
    @TestVisible
    private static Integer globalDescribeInvocationCount = 0;

    private static Map<String, Schema.SObjectType> getObjectTypeCache() {
        if (objectTypesByLowerName == null) {
            globalDescribeInvocationCount++;

            Map<String, Schema.SObjectType> globalDescribe =
                Schema.getGlobalDescribe();

            objectTypesByLowerName =
                new Map<String, Schema.SObjectType>();

            for (String objectApiName : globalDescribe.keySet()) {
                objectTypesByLowerName.put(
                    objectApiName.toLowerCase(),
                    globalDescribe.get(objectApiName)
                );
            }
        }

        return objectTypesByLowerName;
    }

    public static Schema.SObjectType getSObjectType(String objectName) {
        if (String.isBlank(objectName)) {
            throw new ConfigReportException(
                'Object name must not be blank.'
            );
        }

        String normalizedName = objectName.trim().toLowerCase();

        Schema.SObjectType objectType =
            getObjectTypeCache().get(normalizedName);

        if (objectType == null) {
            throw new ConfigReportException(
                'Unknown object: "' + objectName + '".'
            );
        }

        Schema.DescribeSObjectResult objectDescribe =
            objectType.getDescribe();

        if (!objectDescribe.isAccessible()) {
            throw new ConfigReportException(
                'Object is not accessible: "' +
                objectDescribe.getName() +
                '".'
            );
        }

        return objectType;
    }

    public static Set<String> getAccessibleFields(String objectName) {
        Schema.SObjectType objectType = getSObjectType(objectName);
        String canonicalObjectName =
            objectType.getDescribe().getName();

        String cacheKey = canonicalObjectName.toLowerCase();

        if (accessibleFieldCache.containsKey(cacheKey)) {
            return accessibleFieldCache.get(cacheKey).clone();
        }

        Set<String> accessibleFields = new Set<String>();

        Map<String, Schema.SObjectField> fieldMap =
            objectType.getDescribe().fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (fieldDescribe.isAccessible()) {
                accessibleFields.add(fieldDescribe.getName());
            }
        }

        accessibleFieldCache.put(cacheKey, accessibleFields);

        return accessibleFields.clone();
    }

    public static Schema.DescribeFieldResult resolveFieldPath(
        String objectName,
        String path
    ) {
        if (String.isBlank(path)) {
            throw new ConfigReportException(
                'Field path must not be blank for object "' +
                objectName +
                '".'
            );
        }

        Schema.SObjectType rootObjectType =
            getSObjectType(objectName);

        String canonicalObjectName =
            rootObjectType.getDescribe().getName();

        String normalizedPath = path.trim();

        String cacheKey =
            canonicalObjectName.toLowerCase() +
            ':' +
            normalizedPath.toLowerCase();

        if (fieldPathCache.containsKey(cacheKey)) {
            return fieldPathCache.get(cacheKey);
        }

        List<String> segments = normalizedPath.split('\\.');

        /*
         * Account.Owner.Name path 3 segment.
         */
        if (segments.size() > 3) {
            throw new ConfigReportException(
                'Field path "' +
                path +
                '" exceeds the maximum depth of 3 segments.'
            );
        }

        Schema.SObjectType currentObjectType = rootObjectType;
        Schema.DescribeFieldResult finalFieldDescribe;

        for (Integer index = 0; index < segments.size(); index++) {
            String segment = segments[index];

            if (String.isBlank(segment)) {
                throw invalidPath(
                    objectName,
                    path,
                    segment,
                    index
                );
            }

            Boolean isLastSegment =
                index == segments.size() - 1;

            if (isLastSegment) {
                Schema.SObjectField fieldToken =
                    findFieldByApiName(
                        currentObjectType,
                        segment
                    );

                if (fieldToken == null) {
                    throw invalidPath(
                        objectName,
                        path,
                        segment,
                        index
                    );
                }

                finalFieldDescribe =
                    fieldToken.getDescribe();

                if (!finalFieldDescribe.isAccessible()) {
                    throw new ConfigReportException(
                        'Field "' +
                        path +
                        '" is not accessible. Invalid segment: "' +
                        segment +
                        '".'
                    );
                }

                break;
            }

            RelationshipResolution relationship =
                findRelationship(
                    currentObjectType,
                    segment
                );

            if (relationship == null) {
                throw invalidPath(
                    objectName,
                    path,
                    segment,
                    index
                );
            }

            Schema.DescribeFieldResult relationshipFieldDescribe =
                relationship.referenceField.getDescribe();

            if (!relationshipFieldDescribe.isAccessible()) {
                throw new ConfigReportException(
                    'Relationship field for segment "' +
                    segment +
                    '" in path "' +
                    path +
                    '" is not accessible.'
                );
            }

            currentObjectType =
                relationship.targetObjectType;

            if (!currentObjectType.getDescribe().isAccessible()) {
                throw new ConfigReportException(
                    'Referenced object at segment "' +
                    segment +
                    '" in path "' +
                    path +
                    '" is not accessible.'
                );
            }
        }

        fieldPathCache.put(
            cacheKey,
            finalFieldDescribe
        );

        return finalFieldDescribe;
    }

    public static Boolean isFilterable(
        String objectName,
        String path
    ) {
        return resolveFieldPath(
            objectName,
            path
        ).isFilterable();
    }

    public static Boolean isSortable(
        String objectName,
        String path
    ) {
        return resolveFieldPath(
            objectName,
            path
        ).isSortable();
    }

    private static Schema.SObjectField findFieldByApiName(
        Schema.SObjectType objectType,
        String requestedFieldName
    ) {
        Map<String, Schema.SObjectField> fields =
            objectType.getDescribe().fields.getMap();

        for (String actualFieldName : fields.keySet()) {
            if (
                actualFieldName.equalsIgnoreCase(
                    requestedFieldName
                )
            ) {
                return fields.get(actualFieldName);
            }
        }

        return null;
    }

    private static RelationshipResolution findRelationship(
        Schema.SObjectType objectType,
        String requestedRelationshipName
    ) {
        Map<String, Schema.SObjectField> fields =
            objectType.getDescribe().fields.getMap();

        for (Schema.SObjectField fieldToken : fields.values()) {
            Schema.DescribeFieldResult fieldDescribe =
                fieldToken.getDescribe();

            String relationshipName =
                fieldDescribe.getRelationshipName();

            if (
                relationshipName == null ||
                !relationshipName.equalsIgnoreCase(
                    requestedRelationshipName
                )
            ) {
                continue;
            }

            List<Schema.SObjectType> referenceTargets =
                fieldDescribe.getReferenceTo();

            /*
             * OwnerId could be polymorphic reference.
             * Nếu có nhiều target thì không nên tự đoán target.
             */
            if (referenceTargets.size() != 1) {
                throw new ConfigReportException(
                    'Relationship segment "' +
                    requestedRelationshipName +
                    '" is polymorphic and cannot be resolved safely.'
                );
            }

            RelationshipResolution result =
                new RelationshipResolution();

            result.referenceField = fieldToken;
            result.targetObjectType = referenceTargets[0];

            return result;
        }

        return null;
    }

    private static ConfigReportException invalidPath(
        String objectName,
        String fullPath,
        String invalidSegment,
        Integer segmentIndex
    ) {
        return new ConfigReportException(
            'Invalid field path "' +
            fullPath +
            '" for object "' +
            objectName +
            '". Invalid segment "' +
            invalidSegment +
            '" at position ' +
            String.valueOf(segmentIndex + 1) +
            '.'
        );
    }

    @TestVisible
    private static void resetCache() {
        objectTypesByLowerName = null;
        accessibleFieldCache.clear();
        fieldPathCache.clear();
        globalDescribeInvocationCount = 0;
    }

    private class RelationshipResolution {
        private Schema.SObjectField referenceField;
        private Schema.SObjectType targetObjectType;
    }
}