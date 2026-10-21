@IsTest
private class SchemaHelperTest {
  @IsTest
  static void getSObjectType_fiftyCalls_shouldDescribeOnlyOnce() {
    List<String> variants = new List<String>{ 'Case', 'case', 'CASE', 'CaSe' };

    for (Integer i = 0; i < 50; i++) {
      Schema.SObjectType actual = SchemaHelper.getSObjectType(
        variants[Math.mod(i, variants.size())]
      );

      Assert.areEqual(Case.SObjectType, actual);
    }

    Assert.areEqual(
      1,
      SchemaHelper.getTypeObjectsCallCount,
      'Fifty case-insensitive requests for Case must ' +
      'execute Schema.describeSObjects() only once.'
    );
  }

  @IsTest
  static void getSObjectTypes_shouldBulkLoadUniqueObjects() {
    List<Schema.SObjectType> actual = SchemaHelper.getSObjectTypes(
      new List<String>{ 'Case', 'Account', 'case', 'Contact', 'ACCOUNT' }
    );

    Assert.areEqual(5, actual.size());
    Assert.areEqual(Case.SObjectType, actual[0]);
    Assert.areEqual(Account.SObjectType, actual[1]);
    Assert.areEqual(Case.SObjectType, actual[2]);
    Assert.areEqual(Contact.SObjectType, actual[3]);
    Assert.areEqual(Account.SObjectType, actual[4]);

    Assert.areEqual(
      1,
      SchemaHelper.getTypeObjectsCallCount,
      'Unique cache misses must share one bulk describe call.'
    );
  }

  @IsTest
  static void getAccessibleFields_shouldReturnReadableFieldsAndUseSafeCopy() {
    Set<String> firstResult = SchemaHelper.getAccessibleFields('Case');

    Assert.isNotNull(firstResult);
    Assert.isTrue(
      firstResult.contains('Id'),
      'Case.Id should be accessible to the running test user.'
    );

    firstResult.clear();

    Set<String> secondResult = SchemaHelper.getAccessibleFields('CASE');
    Assert.isTrue(
      secondResult.contains('Id'),
      'Changing the returned set must not modify the internal cache.'
    );
  }

  @IsTest
  static void resolveFieldPath_threeLevelRelationship_shouldReturnFinalField() {
    Schema.DescribeFieldResult result = SchemaHelper.resolveFieldPath(
      'Case',
      'account.owner.name'
    );

    Assert.isNotNull(result);

    Assert.areEqual(
      'Name',
      result.getName(),
      'The final field should be User.Name.'
    );

    Assert.areEqual(
      Schema.DisplayType.STRING,
      result.getType(),
      'User.Name should resolve as a String field.'
    );

    Assert.isTrue(
      result.isAccessible(),
      'The resolved final field should be accessible.'
    );

    Assert.areEqual(
      'Account.Owner.Name',
      SchemaHelper.normalizeFieldPath('CASE', 'account.owner.name'),
      'The helper should return the canonical relationship path.'
    );
  }

  @IsTest
  static void resolveFieldPath_moreThanThreeSegments_shouldThrow() {
    try {
      SchemaHelper.resolveFieldPath('Case', 'Account.Owner.Manager.Name');
      Assert.fail('Expected DbQueryException for more than three segments.');
    } catch (DbQueryException e) {
      Assert.isTrue(
        e.getMessage().contains('Field path exceeds three segments'),
        'Exception should explain the three-segment limit.'
      );
      Assert.isTrue(
        e.getMessage().contains('Account.Owner.Manager.Name'),
        'Exception should include the invalid path.'
      );
    }
  }

  @IsTest
  static void resolveFieldPath_invalidRelationship_shouldIdentifySegment() {
    try {
      SchemaHelper.resolveFieldPath('Case', 'InvalidRelationship.Name');
      Assert.fail('Expected DbQueryException for invalid relationship.');
    } catch (DbQueryException e) {
      Assert.isTrue(
        e.getMessage().contains('InvalidRelationship'),
        'Exception should identify the invalid segment.'
      );
      Assert.isTrue(
        e.getMessage().contains('InvalidRelationship.Name'),
        'Exception should include the full invalid path.'
      );
    }
  }

  @IsTest
  static void resolveFieldPath_invalidFinalField_shouldIdentifySegment() {
    try {
      SchemaHelper.resolveFieldPath('Case', 'Account.Owner.InvalidField');
      Assert.fail('Expected DbQueryException for invalid final field.');
    } catch (DbQueryException e) {
      Assert.isTrue(
        e.getMessage().contains('InvalidField'),
        'Exception should identify the invalid final field.'
      );
      Assert.isTrue(
        e.getMessage().contains('Account.Owner.InvalidField'),
        'Exception should include the full invalid path.'
      );
    }
  }

  @IsTest
  static void fieldCapabilities_shouldReturnFilterableAndSortableMetadata() {
    Assert.isTrue(
      SchemaHelper.isFilterable('Case', 'Subject'),
      'Case.Subject should be filterable.'
    );
    Assert.isTrue(
      SchemaHelper.isSortable('Case', 'CreatedDate'),
      'Case.CreatedDate should be sortable.'
    );
    Assert.isTrue(
      SchemaHelper.isFilterable('Case', 'Account.Owner.Name'),
      'A valid relationship field should expose filterability.'
    );
    Assert.isTrue(
      SchemaHelper.isSortable('Case', 'Account.Owner.Name'),
      'A valid relationship field should expose sortability.'
    );
  }
}
