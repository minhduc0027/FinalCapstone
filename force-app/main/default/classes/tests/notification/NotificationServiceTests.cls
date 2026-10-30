@IsTest
private class NotificationServiceTests {
  //===================================================
  // Test setup
  //===================================================
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Test Account');

    insert account;
  }

  //===================================================
  // Send - empty recipients
  //===================================================
  @IsTest
  static void sendShouldReturnWhenRecipientsAreEmpty() {
    Account account = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    Test.startTest();

    NotificationService.send(
      new Set<Id>(),
      account.Id,
      'Test Notification',
      'Test Body'
    );

    Test.stopTest();

    System.assert(true);
  }

  //===================================================
  // Send - null recipients
  //===================================================
  @IsTest
  static void sendShouldReturnWhenRecipientsAreNull() {
    Account account = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    Test.startTest();

    NotificationService.send(
      null,
      account.Id,
      'Test Notification',
      'Test Body'
    );

    Test.stopTest();

    System.assert(true);
  }

  //===================================================
  // Send - target required
  //===================================================
  @IsTest
  static void sendShouldThrowWhenTargetIsNull() {
    Boolean exceptionThrown = false;

    try {
      NotificationService.send(
        new Set<Id>{ UserInfo.getUserId() },
        null,
        'Test Notification',
        'Test Body'
      );
    } catch (NotificationService.NotificationException e) {
      exceptionThrown = true;

      System.assertEquals('Notification target is required.', e.getMessage());
    }

    System.assertEquals(true, exceptionThrown);
  }

  //===================================================
  // Send - title required
  //===================================================
  @IsTest
  static void sendShouldThrowWhenTitleIsBlank() {
    Account account = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    Boolean exceptionThrown = false;

    try {
      NotificationService.send(
        new Set<Id>{ UserInfo.getUserId() },
        account.Id,
        ' ',
        'Test Body'
      );
    } catch (NotificationService.NotificationException e) {
      exceptionThrown = true;

      System.assertEquals('Notification title is required.', e.getMessage());
    }

    System.assertEquals(true, exceptionThrown);
  }

  //===================================================
  // Send - body required
  //===================================================
  @IsTest
  static void sendShouldThrowWhenBodyIsBlank() {
    Account account = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    Boolean exceptionThrown = false;

    try {
      NotificationService.send(
        new Set<Id>{ UserInfo.getUserId() },
        account.Id,
        'Test Notification',
        ' '
      );
    } catch (NotificationService.NotificationException e) {
      exceptionThrown = true;

      System.assertEquals('Notification body is required.', e.getMessage());
    }

    System.assertEquals(true, exceptionThrown);
  }

  //===================================================
  // Try send - exception is swallowed
  //===================================================
  @IsTest
  static void trySendShouldReturnFalseWhenSendFails() {
    Test.startTest();

    Boolean result = NotificationService.trySend(
      new Set<Id>{ UserInfo.getUserId() },
      null,
      'Test Notification',
      'Test Body'
    );

    Test.stopTest();

    System.assertEquals(false, result);
  }

  //===================================================
  // Try send - empty recipients
  //===================================================
  @IsTest
  static void trySendShouldReturnTrueWhenRecipientsAreEmpty() {
    Account account = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    Test.startTest();

    Boolean result = NotificationService.trySend(
      new Set<Id>(),
      account.Id,
      'Test Notification',
      'Test Body'
    );

    Test.stopTest();

    System.assertEquals(true, result);
  }

  //===================================================
  // Normalize recipients - null
  //===================================================
  @IsTest
  static void normalizeRecipientIdsShouldReturnEmptySetWhenInputIsNull() {
    Set<String> result = NotificationService.normalizeRecipientIds(null);

    System.assertNotEquals(null, result);
    System.assertEquals(0, result.size());
  }

  //===================================================
  // Normalize recipients - valid recipients
  //===================================================
  @IsTest
  static void normalizeRecipientIdsShouldNormalizeIds() {
    Id userId = UserInfo.getUserId();

    Set<String> result = NotificationService.normalizeRecipientIds(
      new Set<Id>{ userId }
    );

    System.assertEquals(1, result.size());
    System.assertEquals(true, result.contains(String.valueOf(userId)));
  }

  //===================================================
  // Notification type - cached
  //===================================================
  @IsTest
  static void getNotificationTypeIdShouldUseCachedValue() {
    Account account = [
      SELECT Id
      FROM Account
      LIMIT 1
    ];

    NotificationService.cachedNotificationTypeId = account.Id;

    Test.startTest();

    Id result = NotificationService.getNotificationTypeId();

    Test.stopTest();

    System.assertEquals(account.Id, result);
  }
}
