import { LightningElement, api } from "lwc";
import { statusLabel, amountLabel } from "c/portalPresentation";

const HISTORY_ICONS = {
  CREATED: "utility:add",
  NEW: "utility:record",
  PENDING_APPROVAL: "utility:clock",
  AWAITING_GOODS: "utility:package",
  INSPECTING: "utility:search",
  RE_CONFIRMING: "utility:refresh",
  REFUND_PROCESSING: "utility:sync",
  COMPLETED: "utility:success",
  REFUND_FAILED: "utility:warning",
  REJECTED: "utility:error",
  CANCELLED: "utility:close"
};

export default class ReturnRequestSummary extends LightningElement {
  @api request;
  @api showProducts = false;
  @api showAmount = false;

  get hasRejectionReason() {
    return (
      this.request?.status === "REJECTED" &&
      Boolean(this.request?.rejectionReason?.trim())
    );
  }

  get statusText() {
    return statusLabel(this.request?.status);
  }

  get amountTitle() {
    return amountLabel(this.request || {});
  }

  get hasAmount() {
    return (
      this.request?.refundAmount !== null &&
      this.request?.refundAmount !== undefined
    );
  }

  get products() {
    return (this.request?.lines || []).map((line, index) => ({
      ...line,
      key: String(index)
    }));
  }

  get history() {
    return (this.request?.history || []).map((change, index) => ({
      ...change,
      key: String(index),
      label: statusLabel(change.status),
      iconName: HISTORY_ICONS[change.status] || "utility:record"
    }));
  }

  get hasProducts() {
    return this.showProducts && this.products.length > 0;
  }

  @api focusHeading() {
    this.template.querySelector("h2")?.focus();
  }
}
