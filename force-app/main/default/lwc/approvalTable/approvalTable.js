import { LightningElement, api } from "lwc";

const ROW_ACTIONS = [
  { label: "Approve", name: "approve" },
  { label: "Reject", name: "reject" }
];

const COLUMNS = [
  {
    label: "Request",
    fieldName: "requestUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "requestName" }, target: "_self" }
  },
  { label: "Customer", fieldName: "customerName", type: "text" },
  { label: "Store", fieldName: "storeName", type: "text" },
  {
    label: "Level",
    fieldName: "approvalLevel",
    type: "text",
    initialWidth: 100
  },
  { label: "Status", fieldName: "statusLabel", type: "text" },
  {
    label: "Estimated",
    fieldName: "estimatedRefundAmount",
    type: "currency",
    typeAttributes: { currencyCode: "VND", maximumFractionDigits: 0 }
  },
  {
    label: "Actual",
    fieldName: "actualRefundAmount",
    type: "currency",
    typeAttributes: { currencyCode: "VND", maximumFractionDigits: 0 }
  },
  {
    label: "Due at",
    fieldName: "approvalDueAt",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  {
    label: "Overdue",
    fieldName: "overdueLabel",
    type: "text",
    initialWidth: 90,
    cellAttributes: { class: { fieldName: "overdueClass" } }
  },
  { type: "action", typeAttributes: { rowActions: ROW_ACTIONS } }
];

export default class ApprovalTable extends LightningElement {
  columns = COLUMNS;
  _rows = [];

  @api
  get rows() {
    return this._rows;
  }
  set rows(value) {
    this._rows = (value || []).map((row) => ({
      ...row,
      requestUrl: `/lightning/r/Return_Request__c/${row.requestId}/view`,
      statusLabel: this.statusLabel(row.status),
      overdueLabel: row.overdue ? "Overdue" : "Pending",
      overdueClass: row.overdue
        ? "slds-text-color_error slds-text-title_bold"
        : ""
    }));
  }

  get hasRows() {
    return this._rows.length > 0;
  }

  handleRowSelection(event) {
    const selectedIds = event.detail.selectedRows.map((row) => row.requestId);
    this.dispatchEvent(
      new CustomEvent("selectionchange", { detail: { selectedIds } })
    );
  }

  handleRowAction(event) {
    const { action, row } = event.detail;
    const eventName = action.name === "approve" ? "rowapprove" : "rowreject";
    this.dispatchEvent(
      new CustomEvent(eventName, { detail: { requestId: row.requestId } })
    );
  }

  statusLabel(value) {
    return value === "RE_CONFIRMING"
      ? "Re-confirm"
      : value === "PENDING_APPROVAL"
        ? "Pending Approval"
        : value;
  }
}
