public with sharing class SchemaHelper {
  @TestVisible
  private static Integer globalDescribeInvocationCount = 0;

  private static Map<String, Schema.SObjectType> objectTypes = new Map<String, Schema.SObjectType>();
  private static Map<String, Set<String>> accessibleFields = new Map<String, Set<String>>();
  private static Map<String, Schema.DescribeFieldResult> resolvedFields = new Map<String, Schema.DescribeFieldResult>();
  private static Map<String, String> normalizedPaths = new Map<String, String>();

  public static List<Schema.SObjectType> getSObjectTypes(
    List<String> objectNames
  ) {
    if (objectNames == null || objectNames.isEmpty()) {
      throw new DbQueryException('At least 1 object name required');
    }

    for (String objectName : objectNames) {
      if (String.isBlank(objectName)) {
        throw new DbQueryException('Object name is required');
      }
    }

    List<String> requestedKeys = new List<String>();
    List<String> missingNames = new List<String>();
    Set<String> missingKeys = new Set<String>();

    for (String objectName : objectNames) {
      String requestedName = objectName.trim();
      String key = requestedName.toLowerCase();

      requestedKeys.add(key);

      if (!objectTypes.containsKey(key) && missingKeys.add(key)) {
        missingNames.add(requestedName);
      }
    }

    loadObjectTypes(missingNames);

    List<Schema.SObjectType> results = new List<Schema.SObjectType>();

    for (Integer i = 0; i < requestedKeys.size(); i++) {
      String key = requestedKeys[i];
      Schema.SObjectType objectType = objectTypes.get(key);

      if (objectType == null) {
        throw new DbQueryException('Unknown object: ' + objectNames[i]);
      }

      results.add(objectType);
    }

    return results;
  }

  public static Schema.SObjectType getSObjectType(String objectName) {
    return getSObjectTypes(new List<String>{ objectName })[0];
  }

  public static Set<String> getAccessibleFields(String objectName) {
    Schema.SObjectType token = getSObjectType(objectName);
    String key =
      UserInfo.getUserId() +
      ':' +
      token.getDescribe().getName().toLowerCase();

    if (!accessibleFields.containsKey(key)) {
      Set<String> result = new Set<String>();
      for (
        Schema.SObjectField fieldToken : token.getDescribe()
          .fields.getMap()
          .values()
      ) {
        if (fieldToken.getDescribe().isAccessible()) {
          result.add(fieldToken.getDescribe().getName());
        }
      }

      accessibleFields.put(key, result);
    }

    return new Set<String>(accessibleFields.get(key));
  }

  public static Schema.DescribeFieldResult resolveFieldPath(
    String objectName,
    String path
  ) {
    resolvePath(objectName, path);
    return resolvedFields.get(cacheKey(objectName, path));
  }

  public static String normalizeFieldPath(String objectName, String path) {
    resolvePath(objectName, path);
    return normalizedPaths.get(cacheKey(objectName, path));
  }

  public static Boolean isFilterable(String objectName, String path) {
    return resolveFieldPath(objectName, path).isFilterable();
  }

  public static Boolean isSortable(String objectName, String path) {
    return resolveFieldPath(objectName, path).isSortable();
  }

  private static void loadObjectTypes(List<String> objectNames) {
    if (objectNames == null || objectNames.isEmpty()) {
      return;
    }

    try {
      globalDescribeInvocationCount++;
      List<Schema.DescribeSObjectResult> descriptions = Schema.describeSObjects(
        objectNames,
        SObjectDescribeOptions.DEFERRED
      );

      for (Schema.DescribeSObjectResult description : descriptions) {
        String normalizedKey = description.getName().toLowerCase();
        objectTypes.put(normalizedKey, description.getSObjectType());
      }
    } catch (Exception e) {
      throw new DbQueryException(
        'Unable to resolve objects: ' +
          String.join(objectNames, ', ') +
          '. ' +
          e.getMessage()
      );
    }
  }

  private static void resolvePath(String objectName, String path) {
    if (String.isBlank(objectName)) {
      throw new DbQueryException('Object name is required');
    }
    if (String.isBlank(path)) {
      throw new DbQueryException('Field path is required');
    }
    String key = cacheKey(objectName, path);
    if (resolvedFields.containsKey(key)) {
      return;
    }

    List<String> segments = path.trim().split('\\.');
    if (segments.size() > 3) {
      throw new DbQueryException('Field path exceeds three segments: ' + path);
    }
    Schema.SObjectType currentObjectType = getSObjectType(objectName);
    List<Schema.SObjectType> currentTypes = new List<Schema.SObjectType>{
      currentObjectType
    };

    List<String> normalized = new List<String>();
    Schema.DescribeFieldResult finalDescribe;
    for (Integer i = 0; i < segments.size(); i++) {
      String segment = segments[i];
      Boolean isLast = i == segments.size() - 1;
      if (String.isBlank(segment)) {
        throw invalidSegment(path, segment);
      }

      if (isLast) {
        for (Schema.SObjectType currentType : currentTypes) {
          Schema.SObjectField token = findField(currentType, segment);
          if (token == null || !token.getDescribe().isAccessible()) {
            throw invalidSegment(path, segment);
          }
          Schema.DescribeFieldResult describe = token.getDescribe();
          if (
            finalDescribe != null &&
            finalDescribe.getType() != describe.getType()
          ) {
            throw invalidSegment(path, segment);
          }
          finalDescribe = describe;
        }
        normalized.add(finalDescribe.getName());
      } else {
        List<Schema.SObjectType> nextTypes = new List<Schema.SObjectType>();
        String canonicalRelationship;
        for (Schema.SObjectType currentType : currentTypes) {
          Schema.DescribeFieldResult relationship = findRelationship(
            currentType,
            segment
          );

          if (relationship == null || !relationship.isAccessible()) {
            throw invalidSegment(path, segment);
          }

          if (
            canonicalRelationship != null &&
            canonicalRelationship != relationship.getRelationshipName()
          ) {
            throw invalidSegment(path, segment);
          }

          canonicalRelationship = relationship.getRelationshipName();
          for (
            Schema.SObjectType referenceType : relationship.getReferenceTo()
          ) {
            if (!nextTypes.contains(referenceType)) {
              nextTypes.add(referenceType);
            }
          }
        }

        if (nextTypes.isEmpty()) {
          throw invalidSegment(path, segment);
        }

        normalized.add(canonicalRelationship);
        currentTypes = nextTypes;
      }
    }

    resolvedFields.put(key, finalDescribe);
    normalizedPaths.put(key, String.join(normalized, '.'));
  }

  private static Schema.SObjectField findField(
    Schema.SObjectType token,
    String name
  ) {
    for (String apiName : token.getDescribe().fields.getMap().keySet()) {
      if (apiName.equalsIgnoreCase(name)) {
        return token.getDescribe().fields.getMap().get(apiName);
      }
    }

    return null;
  }

  private static Schema.DescribeFieldResult findRelationship(
    Schema.SObjectType token,
    String name
  ) {
    List<Schema.SObjectField> fields = token.getDescribe()
      .fields.getMap()
      .values();
    for (Schema.SObjectField fieldToken : fields) {
      Schema.DescribeFieldResult field = fieldToken.getDescribe();
      if (
        field.getType() == Schema.DisplayType.REFERENCE &&
        field.getRelationshipName() != null &&
        field.getRelationshipName().equalsIgnoreCase(name)
      ) {
        return field;
      }
    }

    return null;
  }

  private static String cacheKey(String objectName, String path) {
    return UserInfo.getUserId() +
      ':' +
      String.valueOf(objectName).trim().toLowerCase() +
      ':' +
      String.valueOf(path).trim().toLowerCase();
  }

  private static DbQueryException invalidSegment(String path, String segment) {
    return new DbQueryException(
      'Invalid or inaccessible segment "' +
        segment +
        '" in path "' +
        path +
        '".'
    );
  }

  @TestVisible
  private static void resetCache() {
    objectTypes.clear();
    accessibleFields.clear();
    resolvedFields.clear();    
    normalizedPaths.clear();
    globalDescribeInvocationCount = 0;
  }
}
