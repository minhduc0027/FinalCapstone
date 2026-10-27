import { LightningElement } from "lwc";
export default class InspectionWorklistFilters extends LightningElement {
  sourceChannel = "";
  storeId = null;
  fromDate = null;
  toDate = null;
  get channelOptions() {
    return [
      { label: "All channels", value: "" },
      { label: "App", value: "APP" },
      { label: "POS", value: "POS" },
      { label: "Store", value: "STORE" }
    ];
  }
  handleInput(event) {
    const field = event.target.dataset.field;
    this[field] = event.detail?.value ?? event.target.value;
  }
  handleStore(event) {
    this.storeId = event.detail.recordId || null;
  }
  apply() {
    const to = this.template.querySelector('[data-field="toDate"]');
    to.setCustomValidity("");
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      to.setCustomValidity("To date must be on or after From date.");
      to.reportValidity();
      return;
    }
    this.dispatchEvent(
      new CustomEvent("filterchange", {
        detail: {
          sourceChannel: this.sourceChannel || null,
          storeId: this.storeId,
          fromDate: this.fromDate,
          toDate: this.toDate
        }
      })
    );
  }
  reset() {
    this.sourceChannel = "";
    this.storeId = null;
    this.fromDate = null;
    this.toDate = null;
    this.apply();
  }
}
