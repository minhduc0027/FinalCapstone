import { LightningElement, api } from "lwc";

const ROW_ACTIONS = [
  { label: "Approve", name: "approve" },
  { label: "Reject", name: "reject" }
];

const BASE_COLUMNS = [
  {
    label: "Request",
    fieldName: "requestUrl",
    type: "url",
    typeAttributes: {
      label: { fieldName: "requestName" },
      target: "_self"
    }
  },
  {
    label: "Customer",
    fieldName: "customerName",
    type: "text"
  },
  {
    label: "Phone",
    fieldName: "customerPhone",
    type: "phone"
  },
  {
    label: "Order",
    fieldName: "orderNumber",
    type: "text"
  },
  {
    label: "Store",
    fieldName: "storeName",
    type: "text"
  },
  {
    label: "Status",
    fieldName: "statusLabel",
    type: "text"
  },
  {
    label: "Estimated",
    fieldName: "estimatedRefundAmount",
    type: "currency",
    typeAttributes: {
      currencyCode: "VND",
      maximumFractionDigits: 0
    }
  },
  {
    label: "Actual",
    fieldName: "actualRefundAmount",
    type: "currency",
    typeAttributes: {
      currencyCode: "VND",
      maximumFractionDigits: 0
    }
  },
  {
    label: "Created at",
    fieldName: "createdDate",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  }
];

const APPROVAL_ONLY_COLUMNS = [
  {
    label: "Level",
    fieldName: "approvalLevel",
    type: "text",
    initialWidth: 100
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
    cellAttributes: {
      class: { fieldName: "overdueClass" }
    }
  }
];

const ACTION_COLUMN = {
  type: "action",
  typeAttributes: {
    rowActions: ROW_ACTIONS
  }
};

export default class ApprovalTable extends LightningElement {
  @api readOnly = false;

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

  get visibleColumns() {
    if (this.readOnly) {
      return BASE_COLUMNS;
    }

    const approvalColumns = [
      ...BASE_COLUMNS.slice(0, 2),
      ...APPROVAL_ONLY_COLUMNS.slice(0, 1),
      ...BASE_COLUMNS.slice(4),
      ...APPROVAL_ONLY_COLUMNS.slice(1),
      ACTION_COLUMN
    ];

    return approvalColumns;
  }

  get hideCheckboxColumn() {
    return this.readOnly;
  }

  get hasRows() {
    return this._rows.length > 0;
  }

  handleRowSelection(event) {
    if (this.readOnly) {
      return;
    }

    const selectedIds = event.detail.selectedRows.map((row) => row.requestId);

    this.dispatchEvent(
      new CustomEvent("selectionchange", {
        detail: { selectedIds }
      })
    );
  }

  handleRowAction(event) {
    if (this.readOnly) {
      return;
    }

    const { action, row } = event.detail;
    const eventName = action.name === "approve" ? "rowapprove" : "rowreject";

    this.dispatchEvent(
      new CustomEvent(eventName, {
        detail: { requestId: row.requestId }
      })
    );
  }

  statusLabel(value) {
    const labels = {
      RE_CONFIRMING: "Re-confirm",
      PENDING_APPROVAL: "Pending Approval",
      PENDING_INSPECTION: "Pending Inspection",
      INSPECTION_COMPLETED: "Inspection Completed",
      APPROVED: "Approved",
      REJECTED: "Rejected",
      REFUND_PROCESSING: "Refund Processing",
      AWAITING_GOODS: "Awaiting Goods",
      INSPECTING: "Inspecting"
    };

    return labels[value] || value;
  }
}
