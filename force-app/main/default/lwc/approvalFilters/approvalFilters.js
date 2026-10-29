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
const SORT_DIRECTION_OPTIONS = [
  { label: "Ascending", value: "ASC" },
  { label: "Descending", value: "DESC" }
];

export default class ApprovalFilters extends LightningElement {
  approvalLevel = "";
  storeId = null;
  customerId = null;
  fromDate = null;
  toDate = null;
  sortBy = "Approval_Due_At__c";
  sortDirection = "ASC";
  pageSize = "20";

  get sortOptions() {
    return SORT_OPTIONS;
  }
  get levelOptions() {
    return LEVEL_OPTIONS;
  }
  get sortDirections() {
    return SORT_DIRECTION_OPTIONS;
  }
  get pageSizeOptions() {
    return [
      { label: "5 rows", value: "5" },
      { label: "10 rows", value: "10" },
      { label: "20 rows", value: "20" },
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
  handleCustomerChange(event) {
    this.customerId = event.detail.recordId || null;
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
          customerId: this.customerId,
          sortDescending: this.sortDirection === "DESC",
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
    this.customerId = null;
    this.sortBy = "Approval_Due_At__c";
    this.sortDirection = "ASC";
    this.pageSize = "20";
    this.handleApply();
  }
}
