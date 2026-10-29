import { LightningElement } from "lwc";
import getReturnRequests from "@salesforce/apex/CustomerServiceController.getReturnRequests";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const PAGE_SIZE = 20;

export default class CustomerServiceRequestLookup extends LightningElement {
  rows = [];
  isLoading = false;
  hasNext = false;
  currentOffset = 0;

  filter = {
    customerPhone: null,
    orderNumber: null,
    customerName: null,
    pageSize: PAGE_SIZE,
    page: {
      strategy: "OFFSET",
      offsetSize: 0
    }
  };

  get disablePrevious() {
    return this.currentOffset === 0 || this.isLoading;
  }

  get disableNext() {
    return !this.hasNext || this.isLoading;
  }

  get pageLabel() {
    if (!this.rows.length) {
      return "0";
    }

    const start = this.currentOffset + 1;
    const end = this.currentOffset + this.rows.length;

    return `${start} - ${end}`;
  }

  async handleSearch(event) {
    this.currentOffset = 0;

    this.filter = {
      ...this.filter,
      ...event.detail,
      page: {
        strategy: "OFFSET",
        offsetSize: 0
      }
    };

    await this.loadRequests();
  }

  async handlePrevious() {
    if (this.currentOffset === 0 || this.isLoading) {
      return;
    }

    this.currentOffset = Math.max(0, this.currentOffset - PAGE_SIZE);

    await this.loadRequests();
  }

  async handleNext() {
    if (!this.hasNext || this.isLoading) {
      return;
    }

    this.currentOffset += PAGE_SIZE;
    await this.loadRequests();
  }

  async loadRequests() {
    this.isLoading = true;

    const requestFilter = {
      ...this.filter,
      pageSize: PAGE_SIZE,
      page: {
        strategy: "OFFSET",
        offsetSize: this.currentOffset
      }
    };

    try {
      const result = await getReturnRequests({
        filter: requestFilter
      });

      this.rows = result?.records || [];
      this.hasNext = Boolean(result?.hasNext);
      this.filter = requestFilter;
    } catch (error) {
      this.rows = [];
      this.hasNext = false;
      this.showError("Unable to search return requests", error);
    } finally {
      this.isLoading = false;
    }
  }

  showError(title, error) {
    const message =
      error?.body?.message || error?.message || "Unexpected error";

    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant: "error"
      })
    );
  }
}
