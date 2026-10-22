global class ApprovalEscalationBatchScheduler implements Schedulable {
  global void execute(SchedulableContext sc) {
    ApprovalEscalationBatch batch = new ApprovalEscalationBatch();
    Database.executeBatch(batch, 200);
  }
}
