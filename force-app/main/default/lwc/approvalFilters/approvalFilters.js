import { LightningElement } from "lwc";

const SORT_OPTIONS = [
  { label: "Approval due date", value: "Approval_Due_At__c" },
  { label: "Created date", value: "CreatedDate" },
  { label: "Estimated refund", value: "Estimated_Refund_Amount__c" },
  { label: "Actual refund", value: "Actual_Refund_Amount__c" },
  { label: "Approval level", value: "Required_Approval_Level__c" }
];

const LEVEL_OPTIONS = [
  { label: "All levels", value: "" },
  { label: "Store Manager (CHT)", value: "CHT" },
  { label: "Regional Manager (QLV)", value: "QLV" }
];

export default class ApprovalFilters extends LightningElement {
  approvalLevel = "";
  storeId = null;
  fromDate = null;
  toDate = null;
  sortBy = "Approval_Due_At__c";
  sortDescending = false;
  pageSize = "20";

  get sortOptions() {
    return SORT_OPTIONS;
  }
  get levelOptions() {
    return LEVEL_OPTIONS;
  }
  get pageSizeOptions() {
    return [
      { label: "20 rows", value: "20" },
      { label: "30 rows", value: "30" },
      { label: "50 rows", value: "50" }
    ];
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    this[field] =
      event.target.type === "toggle"
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
  }

  handleStoreChange(event) {
    this.storeId = event.detail.recordId || null;
  }

  handleApply() {
    const from = this.template.querySelector('[data-field="fromDate"]');
    const to = this.template.querySelector('[data-field="toDate"]');
    from.setCustomValidity("");
    to.setCustomValidity("");
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      to.setCustomValidity("To date must be on or after From date.");
      to.reportValidity();
      return;
    }
    this.dispatchEvent(
      new CustomEvent("filterchange", {
        detail: {
          approvalLevel: this.approvalLevel || null,
          storeId: this.storeId,
          fromDate: this.fromDate,
          toDate: this.toDate,
          sortBy: this.sortBy,
          sortDescending:
            this.sortDescending === true || this.sortDescending === "true",
          pageSize: Number(this.pageSize)
        }
      })
    );
  }

  handleReset() {
    this.approvalLevel = "";
    this.storeId = null;
    this.fromDate = null;
    this.toDate = null;
    this.sortBy = "Approval_Due_At__c";
    this.sortDescending = false;
    this.pageSize = "20";
    this.handleApply();
  }
}
