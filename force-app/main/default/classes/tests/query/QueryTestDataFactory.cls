/** Test records shared by query module tests; no dependency on business modules. */
@IsTest
public with sharing class QueryTestDataFactory {
  public static void createPageAccounts() {
    insert new List<Account>{
      new Account(Name = 'Page A'),
      new Account(Name = 'Page B'),
      new Account(Name = 'Page C'),
      new Account(Name = 'Page D'),
      new Account(Name = 'Page E')
    };
  }
  /** Creates nullable, duplicate sort values across a bulk population. */
  public static void createKeysetRecords() {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 251; i++) {
      accounts.add(
        new Account(
          Name = 'Keyset ' + Math.mod(i, 7),
          NumberOfEmployees = Math.mod(i, 4) == 0 ? null : Math.mod(i, 9),
          AnnualRevenue = Math.mod(i, 4) == 0 ? null : Math.mod(i, 9) * 10.5,
          Phone = Math.mod(i, 4) == 0 ? null : '555-' + Math.mod(i, 9)
        )
      );
    }
    insert accounts;
    List<Contact> contacts = new List<Contact>();
    for (Integer i = 0; i < 251; i++) {
      contacts.add(
        new Contact(
          LastName = 'Keyset Contact ' + i,
          Email = Math.mod(i, 4) == 0
            ? null
            : 'person' + i + '@example.invalid',
          Birthdate = Math.mod(i, 4) == 0
            ? null
            : Date.newInstance(2000, 1, 1).addDays(Math.mod(i, 9)),
          AccountId = Math.mod(i, 4) == 0 ? null : accounts[Math.mod(i, 9)].Id
        )
      );
    }
    insert contacts;
    List<Task> tasks = new List<Task>();
    for (Integer i = 0; i < 251; i++) {
      tasks.add(
        new Task(
          Subject = 'Keyset task',
          IsReminderSet = Math.mod(i, 2) == 0,
          ReminderDateTime = Math.mod(i, 2) == 0
            ? DateTime.newInstanceGmt(2030, 1, 1, 12, 0, 0)
                .addDays(Math.mod(i, 9))
            : null
        )
      );
    }
    insert tasks;
  }
}
