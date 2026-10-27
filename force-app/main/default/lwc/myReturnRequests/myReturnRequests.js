import { LightningElement, api, wire } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import listRequests from "@salesforce/apex/ReturnPortalController.listRequests";
import getRequest from "@salesforce/apex/ReturnPortalController.getRequest";
import { refreshApex } from "@salesforce/apex";
import { statusLabel, amountLabel } from "c/portalPresentation";

export default class MyReturnRequests extends LightningElement {
  @api pageSize = 10;
  @api showProducts = false;
  isGuest = isGuest;
  cursor = null;
  previousCursors = [];
  page;
  listError = "";
  detailError = "";
  selectedNumber;
  detail;
  isLoading = !isGuest;
  isDetailLoading = false;
  listWire;
  detailWire;
  focusDetail = false;

  get effectivePageSize() {
    if (this.isGuest) return undefined;
    const size = Number(this.pageSize);
    return Number.isInteger(size) && size > 0 ? Math.min(size, 50) : 10;
  }

  @wire(listRequests, { pageSize: "$effectivePageSize", cursor: "$cursor" })
  wiredRequests(result) {
    this.listWire = result;
    if (!result.data && !result.error) return;
    this.isLoading = false;
    this.page = result.data;
    this.listError =
      result.error?.body?.message ||
      (result.error ? "Không thể tải danh sách. Vui lòng thử lại." : "");
  }

  @wire(getRequest, { requestNumber: "$selectedNumber" })
  wiredDetail(result) {
    this.detailWire = result;
    if (!result.data && !result.error) return;
    this.isDetailLoading = false;
    this.detail = result.data;
    this.detailError =
      result.error?.body?.message ||
      (result.error ? "Không thể tải yêu cầu. Vui lòng thử lại." : "");
    this.focusDetail = Boolean(result.data);
  }

  get rows() {
    return (this.page?.requests || []).map((request) => ({
      ...request,
      statusText: statusLabel(request.status),
      amountTitle: amountLabel(request),
      hasAmount:
        request.refundAmount !== null && request.refundAmount !== undefined
    }));
  }

  get isEmpty() {
    return (
      !this.isLoading && !this.listError && this.page && this.rows.length === 0
    );
  }

  get previousDisabled() {
    return this.isLoading || this.previousCursors.length === 0;
  }

  get nextDisabled() {
    return this.isLoading || !this.page?.hasNext;
  }

  handleNext() {
    if (this.nextDisabled) return;
    this.previousCursors = [...this.previousCursors, this.cursor];
    this.cursor = this.page.nextCursor;
    this.isLoading = true;
  }

  handlePrevious() {
    if (this.previousDisabled) return;
    const previous = [...this.previousCursors];
    this.cursor = previous.pop();
    this.previousCursors = previous;
    this.isLoading = true;
  }

  handleSelect(event) {
    this.detail = undefined;
    this.detailError = "";
    this.isDetailLoading = true;
    this.selectedNumber = event.currentTarget.dataset.number;
  }

  handleBack() {
    this.selectedNumber = undefined;
    this.detail = undefined;
    this.detailError = "";
  }

  async handleRefresh() {
    const detailMode = Boolean(this.selectedNumber);
    this.isDetailLoading = detailMode;
    this.isLoading = !detailMode;
    try {
      await refreshApex(detailMode ? this.detailWire : this.listWire);
    } catch {
      const message = "Không thể làm mới dữ liệu. Vui lòng thử lại.";
      if (detailMode) this.detailError = message;
      else this.listError = message;
    } finally {
      this.isDetailLoading = false;
      this.isLoading = false;
    }
  }

  renderedCallback() {
    if (this.focusDetail && this.detail) {
      this.focusDetail = false;
      this.template.querySelector("c-return-request-summary")?.focusHeading();
    }
  }
}
