import { LightningElement, api, wire } from "lwc";
import getStatusTimeline from "@salesforce/apex/ReturnRequestController.getStatusTimeline";

export default class ReturnRequestStatusTimeline extends LightningElement {
  @api recordId;
  timelineItems = [];
  error;

  @wire(getStatusTimeline, {
    requestId: "$recordId"
  })
  wiredTimeline({ error, data }) {
    if (data) {
      this.timelineItems = data.map((item) => {
        return {
          ...item,
          label: this.formatStatus(item.currentStatus),
          dotClass: item.currentStatus ? "timeline-dot current" : "timeline-dot"
        };
      });

      this.error = undefined;
    } else if (error) {
      this.timelineItems = [];
      this.error = error.body?.message || error.message;
    }
  }

  formatStatus(status) {
    if (!status) {
      return "";
    }
    return status
      .replaceAll("_", " ")
      .toLowerCase()
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }
}
