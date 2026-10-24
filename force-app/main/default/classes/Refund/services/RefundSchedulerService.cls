public with sharing class RefundSchedulerService {
  public static final String JOB_NAME = 'SmartReturn Refund Dispatcher';

  private static Integer scanInterval() {
    Integer minutes = SmartReturnConfigService.getRefundScanIntervalMinutes();
    if (minutes == null || minutes < 1 || minutes > 60) {
      throw new ScheduleException('Refund scan interval must be 1-60 minutes.');
    }
    return minutes;
  }

  @TestVisible
  private static String cronFor(Datetime fireAt) {
    return String.join(
      new List<String>{
        String.valueOf(fireAt.second()),
        String.valueOf(fireAt.minute()),
        String.valueOf(fireAt.hour()),
        String.valueOf(fireAt.day()),
        String.valueOf(fireAt.month()),
        '?',
        String.valueOf(fireAt.year())
      },
      ' '
    );
  }

  private static Id scheduleNext() {
    Datetime fireAt = System.now().addMinutes(scanInterval());
    return System.schedule(
      JOB_NAME + ' ' + String.valueOf(fireAt.getTime()),
      cronFor(fireAt),
      new RefundRetryScheduler()
    );
  }

  public static Id ensureScheduled() {
    String pattern = JOB_NAME + '%';
    List<CronTrigger> existing = [
      SELECT Id
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE :pattern
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
      WITH USER_MODE
      LIMIT 1
    ];
    return existing.isEmpty() ? scheduleNext() : existing[0].Id;
  }

  public static Id refreshSchedule() {
    String pattern = JOB_NAME + '%';
    List<CronTrigger> existing = [
      SELECT Id
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE :pattern
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
      WITH USER_MODE
    ];
    for (CronTrigger job : existing) {
      System.abortJob(job.Id);
    }
    return scheduleNext();
  }

  public static void run(SchedulableContext context) {
    if (context != null) {
      scheduleNext();
    }
    try {
      RefundService.dispatchDue();
    } catch (Exception e) {
      LogService.error(e, 'RefundSchedulerService', 'run');
      LogService.insertLogs();
    }
  }

  public class ScheduleException extends Exception {
  }
}
