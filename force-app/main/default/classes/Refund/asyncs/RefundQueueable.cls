public with sharing class RefundQueueable implements Queueable, Database.AllowsCallouts {
  private List<Id> refundIds;

  public RefundQueueable(List<Id> refundIds) {
    this.refundIds = refundIds;
  }

  public void execute(QueueableContext context) {
    RefundService.processClaimed(new Set<Id>(refundIds), context.getJobId());
  }
}
