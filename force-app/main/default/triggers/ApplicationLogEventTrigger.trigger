trigger ApplicationLogEventTrigger on Application_Log_Event__e(after insert) {
  ApplicationLogEventHandler.handle(Trigger.new);
}
