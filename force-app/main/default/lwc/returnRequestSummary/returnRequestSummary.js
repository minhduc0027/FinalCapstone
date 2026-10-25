import { LightningElement, api } from "lwc";
import { statusLabel, amountLabel } from "c/portalPresentation";

export default class ReturnRequestSummary extends LightningElement {
  @api request;
  @api showProducts = false;
  @api showAmount = false;

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
      label: statusLabel(change.status)
    }));
  }

  get hasProducts() {
    return this.showProducts && this.products.length > 0;
  }

  @api focusHeading() {
    this.template.querySelector("h2")?.focus();
  }
}
