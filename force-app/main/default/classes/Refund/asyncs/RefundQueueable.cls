public with sharing class RefundQueueable implements Queueable, Database.AllowsCallouts {
  private Id refundId;

  public RefundQueueable(Id refundId) {
    this.refundId = refundId;
  }

  public void execute(QueueableContext context) {
    RefundService.processClaimed(refundId, context.getJobId());
  }
}
