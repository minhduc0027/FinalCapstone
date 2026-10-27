import { LightningElement, track } from "lwc";
import getWorklist from "@salesforce/apex/ApprovalController.getWorklist";
import bulkApprove from "@salesforce/apex/ApprovalController.bulkApprove";
import bulkReject from "@salesforce/apex/ApprovalController.bulkReject";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const STATUS_PENDING = "PENDING_APPROVAL";
const STATUS_RECONFIRMING = "RE_CONFIRMING";

export default class ApprovalWorkList extends LightningElement {
  activeStatus = STATUS_PENDING;
  @track rows = [];
  @track selectedIds = [];
  @track failures = [];
  isLoading = false;
  showRejectModal = false;
  hasNext = false;
  currentOffset = 0;
  pageSize = 20;

  filter = {
    status: STATUS_PENDING,
    approvalLevel: null,
    storeId: null,
    fromDate: null,
    toDate: null,
    sortBy: "Approval_Due_At__c",
    sortDescending: false,
    pageSize: 20,
    page: {
      strategy: "OFFSET",
      offsetSize: 0
    }
  };

  connectedCallback() {
    this.loadWorklist();
  }

  get hasSelection() {
    return this.selectedIds.length > 0;
  }

  get hasSelectionInverse() {
    return !this.hasSelection || this.isLoading;
  }

  get selectedCountLabel() {
    return `${this.selectedIds.length} selected`;
  }

  get pendingTabClass() {
    return this.activeStatus === STATUS_PENDING ? "tab active" : "tab";
  }

  get reconfirmTabClass() {
    return this.activeStatus === STATUS_RECONFIRMING ? "tab active" : "tab";
  }
  get disablePrevious() {
    return this.currentOffset === 0;
  }

  handlePrevious() {
    if (this.currentOffset < this.filter.pageSize) {
      return;
    }
    this.currentOffset -= this.filter.pageSize;
    this.loadWorklist();
  }

  get disableNext() {
    return !this.hasNext;
  }

  handleNext() {
    if (!this.hasNext) {
      return;
    }
    this.currentOffset += this.filter.pageSize;
    this.loadWorklist();
  }

  get pageLabel() {
    if (!this.rows.length) {
      return "0";
    }
    let start = this.currentOffset + 1;
    let end = this.currentOffset + this.rows.length;
    return `${start} - ${end}`;
  }

  async loadWorklist() {
    this.isLoading = true;
    this.failures = [];
    this.filter = {
      ...this.filter,
      page: {
        strategy: "OFFSET",
        offsetSize: this.currentOffset
      }
    };
    try {
      const result = await getWorklist({ filter: this.filter });
      this.rows = result?.records || [];
      this.hasNext = Boolean(result?.hasNext);
      this.selectedIds = [];
    } catch (error) {
      this.rows = [];
      this.showError("Unable to load approval worklist", error);
    } finally {
      this.isLoading = false;
    }
  }

  handleTabClick(event) {
    const status = event.currentTarget.dataset.status;
    if (!status || status === this.activeStatus) return;
    this.currentOffset = 0;
    this.activeStatus = status;
    this.filter = { ...this.filter, status };
    this.loadWorklist();
  }

  handleFilterChange(event) {
    this.currentOffset = 0;
    this.filter = {
      ...this.filter,
      ...event.detail,
      status: this.activeStatus
      //page: null
    };
    this.loadWorklist();
  }

  handleRefresh() {
    this.loadWorklist();
  }

  handleSelectionChange(event) {
    this.selectedIds = event.detail.selectedIds || [];
  }

  handleRowApprove(event) {
    this.executeApprove([event.detail.requestId]);
  }

  handleRowReject(event) {
    this.selectedIds = [event.detail.requestId];
    this.showRejectModal = true;
  }

  handleBulkApprove() {
    this.executeApprove(this.selectedIds);
  }

  handleOpenReject() {
    this.showRejectModal = true;
  }

  handleCloseReject() {
    this.showRejectModal = false;
  }

  async handleRejectSubmit(event) {
    const { reason, staffNote } = event.detail;
    this.isLoading = true;
    try {
      const results = await bulkReject({
        requestIds: this.selectedIds,
        reason,
        staffNote
      });
      this.showRejectModal = false;
      this.processActionResults(results, "rejected");
      if (!this.rows.length && this.currentOffset > 0) {
        this.currentOffset = Math.max(
          0,
          this.currentOffset - this.filter.pageSize
        );

        await this.loadWorklist();
      }
    } catch (error) {
      this.showError("Reject failed", error);
    } finally {
      this.isLoading = false;
    }
  }

  async executeApprove(requestIds) {
    if (!requestIds?.length) return;
    this.isLoading = true;
    try {
      const results = await bulkApprove({ requestIds });
      this.processActionResults(results, "approved");
      if (!this.rows.length && this.currentOffset > 0) {
        this.currentOffset = Math.max(
          0,
          this.currentOffset - this.filter.pageSize
        );

        await this.loadWorklist();
      }
    } catch (error) {
      this.showError("Approval failed", error);
    } finally {
      this.isLoading = false;
    }
  }

  processActionResults(results = [], verb) {
    const successful = results.filter((item) => item.success);
    const failed = results.filter((item) => !item.success);
    this.failures = failed.map((item) => ({
      requestId: item.requestId,
      message: item.message || "Unknown error"
    }));
    const variant = failed.length ? "warning" : "success";
    this.dispatchEvent(
      new ShowToastEvent({
        title: `${successful.length} request(s) ${verb}`,
        message: failed.length
          ? `${failed.length} request(s) failed. Review the messages on the page.`
          : "Action completed successfully.",
        variant
      })
    );
  }

  showError(title, error) {
    const message =
      error?.body?.message || error?.message || "Unexpected error";
    this.dispatchEvent(
      new ShowToastEvent({ title, message, variant: "error" })
    );
  }
}
