import loadCreateReturnPage from "@salesforce/apex/ReturnRequestController.loadCreateReturnPage";
import previewReturn from "@salesforce/apex/ReturnRequestController.previewReturn";
import createReturn from "@salesforce/apex/ReturnRequestController.createReturn";

import { LightningElement, api } from "lwc";

import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const PREVIEW_DELAY_MS = 600;

const REASON_OPTIONS = [
  { label: "Lỗi kỹ thuật", value: "DEFECT" },
  { label: "Giao sai hàng", value: "WRONG_ITEM" },
  { label: "Không vừa ý", value: "NOT_SATISFIED" },
  { label: "Hư hỏng do khách", value: "CUSTOMER_DAMAGED" }
];

const CONDITION_OPTIONS = [
  { label: "Nguyên seal", value: "SEALED" },
  { label: "Đã mở hộp", value: "OPENED" },
  { label: "Có dấu hiệu sử dụng", value: "USED" }
];

export default class CreateReturnRequest extends NavigationMixin(
  LightningElement
) {
  _recordId;
  initializedRecordId;

  header;
  rows = [];

  totalEstimatedRefund = 0;
  approvalLevel;
  canSubmit = false;

  isLoading = false;
  isPreviewing = false;
  isSubmitting = false;

  errorMessage;
  previewTimer;
  previewRequestSequence = 0;

  reasonOptions = REASON_OPTIONS;
  conditionOptions = CONDITION_OPTIONS;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    this._recordId = value;
    if (value && value !== this.initializedRecordId) {
      this.initializedRecordId = value;
      this.loadPage();
    }
  }

  disconnectedCallback() {
    if (this.previewTimer) {
      clearTimeout(this.previewTimer);
    }
  }

  get hasHeader() {
    return Boolean(this.header);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && this.hasHeader && !this.hasRows;
  }

  get showSpinner() {
    return this.isLoading || this.isSubmitting;
  }

  get submitDisabled() {
    return (
      !this.canSubmit ||
      this.isLoading ||
      this.isPreviewing ||
      this.isSubmitting
    );
  }

  get submitLabel() {
    return this.isSubmitting ? "Đang tạo yêu cầu..." : "Tạo yêu cầu";
  }

  get formattedTotalRefund() {
    return this.formatCurrency(this.totalEstimatedRefund);
  }

  get approvalLevelLabel() {
    const labels = {
      AUTO: "Tự động",
      CHT: "Cửa hàng trưởng",
      QLV: "Quản lý vùng"
    };
    return labels[this.approvalLevel] || "Chưa xác định";
  }

  async loadPage() {
    if (!this.recordId) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = undefined;

    try {
      const result = await loadCreateReturnPage({ orderId: this.recordId });
      if (!result?.success) {
        this.handleBusinessError(result);
        return;
      }

      this.header = result.header;
      this.totalEstimatedRefund = result.totalEstimatedRefund || 0;
      this.approvalLevel = result.approvalLevel;
      this.canSubmit = Boolean(result.canSubmit);
      this.rows = (result.lines || []).map((line) => this.mapInitialRow(line));
    } catch (error) {
      this.handleApexError(
        error,
        "Không thể tải thông tin tạo yêu cầu trả hàng."
      );
    } finally {
      this.isLoading = false;
    }
  }

  mapInitialRow(line) {
    const eligible = Boolean(line.eligible);
    return {
      ...line,
      requestedQuantity: line.requestedQuantity || 0,
      reasonCode: line.reasonCode || "",
      conditionCode: line.conditionCode || "",
      refundRate: line.refundRate || 0,
      estimatedRefundAmount: line.estimatedRefundAmount || 0,
      rowDisabled: !eligible,
      quantityDisabled: !eligible,
      reasonDisabled: !eligible,
      conditionDisabled: !eligible,
      rowClass: eligible ? "product-row" : "product-row product-row_disabled",
      formattedUnitPrice: this.formatCurrency(line.unitPricePaid),
      formattedRefundAmount: this.formatCurrency(line.estimatedRefundAmount),
      formattedDeadline: this.formatDate(line.returnDeadline)
    };
  }

  handleQuantityChange(event) {
    const value = event.target.value === "" ? 0 : Number(event.target.value);
    this.updateRow(event.target.dataset.id, "requestedQuantity", value);
  }

  handleReasonChange(event) {
    this.updateRow(event.target.dataset.id, "reasonCode", event.detail.value);
  }

  handleConditionChange(event) {
    this.updateRow(
      event.target.dataset.id,
      "conditionCode",
      event.detail.value
    );
  }

  updateRow(orderItemId, fieldName, value) {
    this.rows = this.rows.map((row) => {
      if (row.orderItemId !== orderItemId) {
        return row;
      }

      const updatedRow = { ...row, [fieldName]: value };
      if (fieldName === "requestedQuantity" && (!value || value <= 0)) {
        updatedRow.refundRate = 0;
        updatedRow.estimatedRefundAmount = 0;
        updatedRow.formattedRefundAmount = this.formatCurrency(0);
        updatedRow.validationMessage = null;
        updatedRow.valid = Boolean(updatedRow.eligible);
      }
      return updatedRow;
    });

    this.schedulePreview();
  }

  schedulePreview() {
    if (this.previewTimer) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      clearTimeout(this.previewTimer);
    }
    this.canSubmit = false;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(
      () => this.calculatePreview(),
      PREVIEW_DELAY_MS
    );
  }

  buildSelectedLineInputs() {
    return this.rows
      .filter((row) => row.eligible && Number(row.requestedQuantity) > 0)
      .map((row) => ({
        orderItemId: row.orderItemId,
        requestedQuantity: Number(row.requestedQuantity),
        reasonCode: row.reasonCode || null,
        conditionCode: row.conditionCode || null
      }));
  }

  buildInput() {
    return {
      orderId: this.recordId,
      sourceChannel: "STORE",
      externalRequestId: null,
      lines: this.buildSelectedLineInputs()
    };
  }

  async calculatePreview() {
    const selectedLines = this.buildSelectedLineInputs();
    if (selectedLines.length === 0) {
      this.resetPreviewSummary();
      return;
    }

    const requestSequence = ++this.previewRequestSequence;
    this.isPreviewing = true;
    this.errorMessage = undefined;

    try {
      const result = await previewReturn({
        input: {
          orderId: this.recordId,
          sourceChannel: "STORE",
          externalRequestId: null,
          lines: selectedLines
        }
      });

      if (requestSequence !== this.previewRequestSequence) {
        return;
      }

      if (!result?.success) {
        this.handleBusinessError(result);
        this.canSubmit = false;
        return;
      }

      this.applyPreviewResult(result);
    } catch (error) {
      if (requestSequence !== this.previewRequestSequence) {
        return;
      }
      this.canSubmit = false;
      this.handleApexError(error, "Không thể tính tiền hoàn dự kiến.");
    } finally {
      if (requestSequence === this.previewRequestSequence) {
        this.isPreviewing = false;
      }
    }
  }

  applyPreviewResult(result) {
    const previewByOrderItemId = new Map(
      (result.lines || []).map((line) => [line.orderItemId, line])
    );

    this.rows = this.rows.map((row) => {
      const preview = previewByOrderItemId.get(row.orderItemId);
      if (!preview) {
        return {
          ...row,
          refundRate: 0,
          estimatedRefundAmount: 0,
          formattedRefundAmount: this.formatCurrency(0),
          validationMessage: null
        };
      }

      return {
        ...row,
        ...preview,

        rowDisabled: !preview.eligible,
        quantityDisabled: !preview.eligible,
        reasonDisabled: !preview.eligible,
        conditionDisabled: !preview.eligible,

        rowClass: preview.eligible
          ? "product-row"
          : "product-row product-row_disabled",

        formattedUnitPrice: this.formatCurrency(preview.unitPricePaid),

        formattedRefundAmount: this.formatCurrency(
          preview.estimatedRefundAmount
        ),

        formattedDeadline: this.formatDate(preview.returnDeadline),

        validationMessage:
          preview.valid === true
            ? null
            : preview.validationMessage || preview.eligibilityReason || null
      };
    });

    this.totalEstimatedRefund = result.totalEstimatedRefund || 0;
    this.approvalLevel = result.approvalLevel;
    this.canSubmit = Boolean(result.canSubmit);
    this.errorMessage = undefined;
  }

  resetPreviewSummary() {
    this.previewRequestSequence++;
    this.totalEstimatedRefund = 0;
    this.approvalLevel = null;
    this.canSubmit = false;
    this.isPreviewing = false;
    this.errorMessage = undefined;
    this.rows = this.rows.map((row) => ({
      ...row,
      refundRate: 0,
      estimatedRefundAmount: 0,
      formattedRefundAmount: this.formatCurrency(0),
      validationMessage: null
    }));
  }

  async handleSubmit() {
    if (this.submitDisabled) {
      return;
    }

    const input = this.buildInput();
    if (input.lines.length === 0) {
      this.showToast(
        "Thiếu dữ liệu",
        "Phải có ít nhất một dòng có số lượng trả lớn hơn 0.",
        "warning"
      );
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = undefined;

    try {
      const result = await createReturn({ input });
      if (!result?.success) {
        this.handleBusinessError(result);
        return;
      }

      this.showToast(
        "Thành công",
        result.message || "Yêu cầu trả hàng đã được tạo thành công.",
        "success"
      );
      this.navigateToReturnRequest(result.returnRequestId);
    } catch (error) {
      this.handleApexError(error, "Không thể tạo yêu cầu trả hàng.");
    } finally {
      this.isSubmitting = false;
    }
  }

  navigateToReturnRequest(returnRequestId) {
    if (!returnRequestId) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: returnRequestId,
        objectApiName: "Return_Request__c",
        actionName: "view"
      }
    });
  }

  handleBusinessError(result) {
    this.errorMessage = result?.message || "Không thể xử lý yêu cầu trả hàng.";
    this.showToast("Không thể xử lý", this.errorMessage, "error");
  }

  handleApexError(error, fallbackMessage) {
    const message = error?.body?.message || error?.message || fallbackMessage;
    this.errorMessage = message;
    this.showToast("Đã xảy ra lỗi", message, "error");
    console.error(error);
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  formatCurrency(value) {
    return new Intl.NumberFormat("vi-VN", {
      style: "currency",
      currency: "VND",
      maximumFractionDigits: 0
    }).format(Number(value || 0));
  }

  formatDate(value) {
    if (!value) {
      return "";
    }

    return new Intl.DateTimeFormat("vi-VN").format(
      new Date(`${value}T00:00:00`)
    );
  }
}
