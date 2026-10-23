public with sharing class RefundRetryScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    RefundService.dispatchDue();
  }
}
