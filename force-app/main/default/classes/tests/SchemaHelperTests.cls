@IsTest
private class SchemaHelperTests {
  @TestSetup
  static void setupData() {
    insert new Account(Name = 'Schema Helper Test');
  }

  @IsTest
  static void getSObjectType_shouldResolveCaseInsensitiveName() {
    SchemaHelper.resetCache();

    Schema.SObjectType firstResult = SchemaHelper.getSObjectType(' Account ');

    Schema.SObjectType secondResult = SchemaHelper.getSObjectType('account');

    System.assertEquals(
      Account.SObjectType,
      firstResult,
      'Account should be resolved case-insensitively.'
    );

    System.assertEquals(
      firstResult,
      secondResult,
      'The cached SObjectType should be reused.'
    );

    System.assertEquals(
      1,
      SchemaHelper.globalDescribeInvocationCount,
      'Global describe should only be invoked once.'
    );
  }

  @IsTest
  static void getSObjectType_shouldRejectBlankObjectName() {
    try {
      SchemaHelper.getSObjectType('   ');
      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('Object name must not be blank'));
    }
  }

  @IsTest
  static void getSObjectType_shouldRejectUnknownObject() {
    try {
      SchemaHelper.getSObjectType('Definitely_Not_An_Object__c');

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('Unknown object'));
    }
  }

  @IsTest
  static void getAccessibleFields_shouldReturnDefensiveClone() {
    SchemaHelper.resetCache();

    Set<String> firstCall = SchemaHelper.getAccessibleFields('Account');

    System.assert(firstCall.contains('Id'), 'Id should be accessible.');

    System.assert(firstCall.contains('Name'), 'Name should be accessible.');

    firstCall.clear();

    Set<String> secondCall = SchemaHelper.getAccessibleFields('account');

    System.assert(
      secondCall.contains('Id'),
      'Changing returned set must not modify cache.'
    );

    System.assert(
      secondCall.contains('Name'),
      'Cached fields should remain unchanged.'
    );
  }

  @IsTest
  static void resolveFieldPath_shouldResolveDirectField() {
    Schema.DescribeFieldResult fieldDescribe = SchemaHelper.resolveFieldPath(
      'Account',
      'Name'
    );

    System.assertEquals('Name', fieldDescribe.getName());

    System.assertEquals(Schema.DisplayType.STRING, fieldDescribe.getType());

    System.assertEquals(true, SchemaHelper.isFilterable('Account', 'Name'));

    System.assertEquals(true, SchemaHelper.isSortable('Account', 'Name'));
  }

  @IsTest
  static void resolveFieldPath_shouldResolveRelationshipField() {
    Schema.DescribeFieldResult fieldDescribe = SchemaHelper.resolveFieldPath(
      'Account',
      'CreatedBy.Name'
    );

    System.assertEquals('Name', fieldDescribe.getName());

    System.assertEquals(Schema.DisplayType.STRING, fieldDescribe.getType());
  }

  @IsTest
  static void resolveFieldPath_shouldUseCache() {
    SchemaHelper.resetCache();

    Schema.DescribeFieldResult firstResult = SchemaHelper.resolveFieldPath(
      'Account',
      'CreatedBy.Name'
    );

    Schema.DescribeFieldResult secondResult = SchemaHelper.resolveFieldPath(
      'account',
      'createdby.name'
    );

    System.assertEquals(firstResult.getName(), secondResult.getName());

    System.assertEquals(
      1,
      SchemaHelper.globalDescribeInvocationCount,
      'Global describe should still run once.'
    );
  }

  @IsTest
  static void resolveFieldPath_shouldRejectBlankPath() {
    try {
      SchemaHelper.resolveFieldPath('Account', ' ');

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('Field path must not be blank'));
    }
  }

  @IsTest
  static void resolveFieldPath_shouldRejectTooDeepPath() {
    try {
      SchemaHelper.resolveFieldPath(
        'Account',
        'CreatedBy.Manager.CreatedBy.Name'
      );

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('exceeds the maximum depth'));
    }
  }

  @IsTest
  static void resolveFieldPath_shouldRejectEmptySegment() {
    try {
      SchemaHelper.resolveFieldPath('Account', 'CreatedBy..Name');

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('Invalid field path'));

      System.assert(ex.getMessage().contains('position 2'));
    }
  }

  @IsTest
  static void resolveFieldPath_shouldRejectUnknownDirectField() {
    try {
      SchemaHelper.resolveFieldPath('Account', 'UnknownField__c');

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('Invalid segment'));
    }
  }

  @IsTest
  static void resolveFieldPath_shouldRejectUnknownRelationship() {
    try {
      SchemaHelper.resolveFieldPath('Account', 'UnknownRelationship__r.Name');

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(ex.getMessage().contains('UnknownRelationship__r'));
    }
  }

  @IsTest
  static void resolveFieldPath_shouldRejectPolymorphicRelationship() {
    /*
     * Task.Who can reference Contact or Lead, so it is
     * a stable standard polymorphic relationship.
     */
    try {
      SchemaHelper.resolveFieldPath('Task', 'Who.Name');

      System.assert(false, 'Expected ConfigReportException.');
    } catch (ConfigReportException ex) {
      System.assert(
        ex.getMessage().contains('polymorphic'),
        'Expected polymorphic relationship exception.'
      );
    }
  }

  @IsTest
  static void resetCache_shouldClearAllCachedState() {
    SchemaHelper.getSObjectType('Account');
    SchemaHelper.getAccessibleFields('Account');
    SchemaHelper.resolveFieldPath('Account', 'Name');

    System.assertEquals(1, SchemaHelper.globalDescribeInvocationCount);

    SchemaHelper.resetCache();

    System.assertEquals(0, SchemaHelper.globalDescribeInvocationCount);

    SchemaHelper.getSObjectType('Contact');

    System.assertEquals(1, SchemaHelper.globalDescribeInvocationCount);
  }
}
