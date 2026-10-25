import { LightningElement, api, wire } from "lwc";
import { MessageContext, publish } from "lightning/messageService";
import COMPLETE_REFUND_CHANNEL from "@salesforce/messageChannel/Refund_Complete__c";

export default class RefundCompleteDialog extends LightningElement {
  @api recordId;
  @wire(MessageContext) messageContext;

  @api invoke() {
    publish(this.messageContext, COMPLETE_REFUND_CHANNEL, {
      recordId: this.recordId
    });
  }
}
