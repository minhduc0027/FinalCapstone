import { LightningElement, wire } from "lwc";
import getStatusTimeline from "@salesforce/apex/ReturnRequestController.getStatusTimeline";
import {
  MessageContext,
  subscribe,
  unsubscribe,
  APPLICATION_SCOPE
} from "lightning/messageService";
import RETURN_REQUEST_SELECTED from "@salesforce/messageChannel/ReturnRequestSelected";
export default class ReturnRequestStatusTimeline extends LightningElement {
  recordId;
  timelineItems = [];
  error;
  subscription;
  isLoading = false;
  @wire(MessageContext) messageContext;
  renderedCallback() {
    if (!this.subscription && this.messageContext) this.subscribeToSelection();
  }
  disconnectedCallback() {
    if (this.subscription) unsubscribe(this.subscription);
  }
  subscribeToSelection() {
    this.subscription = subscribe(
      this.messageContext,
      RETURN_REQUEST_SELECTED,
      (m) => {
        if (m?.requestId) {
          this.recordId = m.requestId;
          this.loadTimeline();
        }
      },
      { scope: APPLICATION_SCOPE }
    );
  }
  async loadTimeline() {
    this.isLoading = true;
    try {
      const data = await getStatusTimeline({ requestId: this.recordId });
      this.timelineItems = (data || []).map((item, index, array) => ({
        ...item,
        uniqueKey: `${item.changedAt}-${index}`,
        label: this.formatStatus(item.currentStatus),
        previousLabel: this.formatStatus(item.previousStatus),
        dotClass:
          index === array.length - 1 ? "timeline-dot current" : "timeline-dot"
      }));
      this.error = undefined;
    } catch (e) {
      this.timelineItems = [];
      this.error = e?.body?.message || e?.message || "Unexpected error";
    } finally {
      this.isLoading = false;
    }
  }
  get hasItems() {
    return this.timelineItems.length > 0;
  }
  get hasSelection() {
    return Boolean(this.recordId);
  }
  formatStatus(status) {
    if (!status) {
      return "";
    }

    return status
      .split("_")
      .filter(Boolean)
      .map((word) => {
        return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
      })
      .join(" ");
  }
}
