trigger ReturnRequestTrigger on Case(before insert, before update) {
  switch on Trigger.operationType {
    when BEFORE_INSERT {
    }
    when BEFORE_UPDATE {
      ReturnRequestTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
  }
}
