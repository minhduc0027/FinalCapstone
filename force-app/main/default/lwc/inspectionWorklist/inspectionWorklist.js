import { LightningElement, wire } from "lwc";
import getWorklist from "@salesforce/apex/InspectionController.getWorklist";
import {
  MessageContext,
  publish,
  subscribe,
  unsubscribe,
  APPLICATION_SCOPE
} from "lightning/messageService";
import RETURN_REQUEST_SELECTED from "@salesforce/messageChannel/ReturnRequestSelected__c";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const OFFSET = "OFFSET";
const PAGE_SIZE = 20;
const COLUMNS = [
  { label: "Request", fieldName: "requestName", type: "text" },
  { label: "Customer", fieldName: "customerName", type: "text" },
  { label: "Store", fieldName: "storeName", type: "text" },
  {
    label: "Channel",
    fieldName: "sourceChannel",
    type: "text",
    initialWidth: 105
  },
  {
    label: "Estimated",
    fieldName: "estimatedRefundAmount",
    type: "currency",
    typeAttributes: { currencyCode: "VND", maximumFractionDigits: 0 }
  },
  {
    label: "Created",
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

export default class InspectionWorklist extends LightningElement {
  columns = COLUMNS;
  rows = [];
  selectedRequestId;
  isLoading = false;
  hasNext = false;
  currentOffset = 0;
  pageSize = PAGE_SIZE;
  subscription;
  filter = {
    storeId: null,
    sourceChannel: null,
    fromDate: null,
    toDate: null,
    sortBy: "CreatedDate",
    sortDescending: false
  };

  @wire(MessageContext) messageContext;

  connectedCallback() {
    this.load();
  }
  renderedCallback() {
    if (!this.subscription && this.messageContext) this.subscribeToMessages();
  }
  disconnectedCallback() {
    if (this.subscription) unsubscribe(this.subscription);
  }

  subscribeToMessages() {
    this.subscription = subscribe(
      this.messageContext,
      RETURN_REQUEST_SELECTED,
      (message) => {
        if (message?.action === "INSPECTION_SAVED") {
          if (message.requestId === this.selectedRequestId)
            this.selectedRequestId = null;
          this.load();
        }
      },
      { scope: APPLICATION_SCOPE }
    );
  }

  get hasRows() {
    return this.rows.length > 0;
  }
  get selectedRows() {
    return this.selectedRequestId ? [this.selectedRequestId] : [];
  }
  get disablePrevious() {
    return this.isLoading || this.currentOffset === 0;
  }
  get disableNext() {
    return this.isLoading || !this.hasNext;
  }
  get pageLabel() {
    return this.rows.length
      ? `${this.currentOffset + 1} - ${this.currentOffset + this.rows.length}`
      : "0";
  }

  buildFilter() {
    return {
      ...this.filter,

      pageSize: this.pageSize,

      page: {
        strategy: OFFSET,
        offsetSize: this.currentOffset,
        afterId: null,
        afterValue: null
      }
    };
  }

  async load() {
    this.isLoading = true;

    try {
      let result = await getWorklist({
        filter: this.buildFilter()
      });

      this.rows = result?.records || [];

      this.hasNext = Boolean(result?.hasNext);

      if (!this.rows.length && this.currentOffset > 0) {
        this.currentOffset = Math.max(0, this.currentOffset - this.pageSize);

        result = await getWorklist({
          filter: this.buildFilter()
        });

        this.rows = result?.records || [];

        this.hasNext = Boolean(result?.hasNext);
      }
    } catch (error) {
      this.rows = [];

      this.toast(
        "Unable to load inspection worklist",
        this.message(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  handleRowSelection(event) {
    const row = event.detail.selectedRows?.[0];
    if (!row) return;
    this.selectedRequestId = row.requestId;
    publish(this.messageContext, RETURN_REQUEST_SELECTED, {
      requestId: row.requestId,
      action: "SELECTED",
      source: "inspectionWorklist"
    });
  }
  handleRefresh() {
    this.load();
  }
  handleNext() {
    if (this.hasNext) {
      this.currentOffset += this.pageSize;
      this.load();
    }
  }
  handlePrevious() {
    this.currentOffset = Math.max(0, this.currentOffset - this.pageSize);
    this.load();
  }
  handleFilterChange(event) {
    this.currentOffset = 0;
    this.filter = { ...this.filter, ...event.detail };
    this.load();
  }
  message(e) {
    return e?.body?.message || e?.message || "Unexpected error";
  }
  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
