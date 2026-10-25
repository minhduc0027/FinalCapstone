public with sharing class RefundRetryScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    RefundSchedulerService.run(context);
  }
}
