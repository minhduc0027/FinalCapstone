import { LightningElement, wire } from "lwc";

import getStatusTimeline from "@salesforce/apex/ReturnRequestController.getStatusTimeline";

import {
  MessageContext,
  subscribe,
  unsubscribe,
  APPLICATION_SCOPE
} from "lightning/messageService";

import RETURN_REQUEST_SELECTED from "@salesforce/messageChannel/ReturnRequestSelected__c";

export default class ReturnRequestStatusTimeline extends LightningElement {
  recordId;
  timelineItems = [];
  error;
  subscription;
  isLoading = false;

  @wire(MessageContext)
  messageContext;

  connectedCallback() {
    this.subscribeToSelection();
  }

  disconnectedCallback() {
    this.unsubscribeFromSelection();
  }

  subscribeToSelection() {
    if (this.subscription || !this.messageContext) {
      return;
    }

    this.subscription = subscribe(
      this.messageContext,
      RETURN_REQUEST_SELECTED,
      (message) => this.handleMessage(message),
      {
        scope: APPLICATION_SCOPE
      }
    );
  }

  unsubscribeFromSelection() {
    if (!this.subscription) {
      return;
    }

    unsubscribe(this.subscription);
    this.subscription = null;
  }

  handleMessage(message) {
    if (!message?.requestId) {
      return;
    }

    /*
     * SELECTED
     *   -> load timeline của request vừa chọn.
     *
     * INSPECTION_SAVED
     *   -> reload timeline để nhận status mới sau inspection.
     */
    this.recordId = message.requestId;
    this.loadTimeline();
  }

  async loadTimeline() {
    const requestId = this.recordId;

    this.isLoading = true;
    this.error = undefined;

    try {
      const data = await getStatusTimeline({
        requestId
      });

      /*
       * User đã chọn request khác trong lúc Apex request cũ
       * vẫn đang chạy.
       */
      if (requestId !== this.recordId) {
        return;
      }

      this.timelineItems = (data || []).map((item, index, array) => ({
        ...item,

        uniqueKey: `${item.changedAt}-${index}`,

        label: this.formatStatus(item.currentStatus),

        previousLabel: this.formatStatus(item.previousStatus),

        dotClass:
          index === array.length - 1 ? "timeline-dot current" : "timeline-dot"
      }));
    } catch (error) {
      if (requestId !== this.recordId) {
        return;
      }

      this.timelineItems = [];

      this.error = error?.body?.message || error?.message || "Unexpected error";
    } finally {
      if (requestId === this.recordId) {
        this.isLoading = false;
      }
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
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join(" ");
  }
}
