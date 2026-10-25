trigger UserTrigger on User(after insert, after update) {
  UserTriggerHandler.handle();
}
