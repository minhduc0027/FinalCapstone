import { LightningElement, wire } from "lwc";
import getReturnRequestLines from "@salesforce/apex/InspectionController.getReturnRequestLines";
import submitInspection from "@salesforce/apex/InspectionController.submitInspection";

import {
  MessageContext,
  publish,
  subscribe,
  unsubscribe,
  APPLICATION_SCOPE
} from "lightning/messageService";

import RETURN_REQUEST_SELECTED from "@salesforce/messageChannel/ReturnRequestSelected__c";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class InspectionLines extends LightningElement {
  recordId;
  rows = [];
  isLoading = false;
  subscription;

  @wire(MessageContext)
  messageContext;

  connectedCallback() {
    this.subscribeToSelection();
  }

  disconnectedCallback() {
    this.unsubscribeFromSelection();
  }

  subscribeToSelection() {
    if (this.subscription || !this.messageContext) {
      return;
    }

    this.subscription = subscribe(
      this.messageContext,
      RETURN_REQUEST_SELECTED,
      (message) => this.handleRequestSelection(message),
      {
        scope: APPLICATION_SCOPE
      }
    );
  }

  unsubscribeFromSelection() {
    if (!this.subscription) {
      return;
    }

    unsubscribe(this.subscription);
    this.subscription = null;
  }

  handleRequestSelection(message) {
    if (message?.action !== "SELECTED" || !message.requestId) {
      return;
    }

    this.recordId = message.requestId;
    this.rows = [];

    this.load();
  }

  get eligibilityOptions() {
    return [
      {
        label: "Eligible",
        value: "true"
      },
      {
        label: "Not eligible",
        value: "false"
      }
    ];
  }

  get hasSelection() {
    return Boolean(this.recordId);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showNoRows() {
    return this.hasSelection && !this.hasRows && !this.isLoading;
  }

  get showNoSelection() {
    return !this.hasSelection && !this.isLoading;
  }

  get disableSubmit() {
    return this.isLoading || !this.hasRows;
  }

  async load() {
    const selectedRequestId = this.recordId;

    this.isLoading = true;

    try {
      const data = await getReturnRequestLines({
        returnRequestId: selectedRequestId
      });

      /*
       * Nếu user chọn request khác khi promise cũ chưa hoàn tất,
       * không ghi dữ liệu cũ đè lên request mới.
       */
      if (selectedRequestId !== this.recordId) {
        return;
      }

      this.rows = (data || [])
        .filter((line) => Boolean(line?.Id))
        .map((line) => this.mapLine(line));
    } catch (error) {
      if (selectedRequestId !== this.recordId) {
        return;
      }

      this.rows = [];

      this.toast(
        "Unable to load inspection lines",
        this.getErrorMessage(error),
        "error"
      );
    } finally {
      if (selectedRequestId === this.recordId) {
        this.isLoading = false;
      }
    }
  }

  mapLine(line) {
    const requestedQuantity = line.Requested_Quantity__c;
    const purchasedQuantity = line.Purchased_Quantity__c;

    const unitPrice =
      line.Order_Item__r?.UnitPrice ?? line.Unit_Price_Paid__c ?? null;

    return {
      id: line.Id,

      productName: line.Product__r?.Name || "Product not available",

      requestedQuantity,
      requestedQuantityDisplay: this.displayValue(requestedQuantity),

      purchasedQuantity,
      purchasedQuantityDisplay: this.displayValue(purchasedQuantity),

      unitPrice,
      hasUnitPrice: unitPrice !== null && unitPrice !== undefined,

      returnReason: line.Return_Reason__c || "—",
      reportedCondition: line.Reported_Condition__c || "—",

      isEligible: this.toEligibilityValue(line.Is_Eligible__c),

      eligibilityCode: line.Eligibility_Code__c || "",
      eligibilityReason: line.Eligibility_Reason__c || ""
    };
  }

  toEligibilityValue(value) {
    if (value === true) {
      return "true";
    }

    if (value === false) {
      return "false";
    }

    return "";
  }

  displayValue(value) {
    return value === null || value === undefined || value === "" ? "—" : value;
  }

  handleFieldChange(event) {
    const id = event.target.dataset.id;
    const field = event.target.dataset.field;

    if (!id || !field) {
      return;
    }

    const value = event.detail?.value ?? event.target.value;

    this.rows = this.rows.map((row) => {
      if (row.id !== id) {
        return row;
      }

      return {
        ...row,
        [field]: value
      };
    });
  }

  validate() {
    let isValid = true;

    const inputs = this.template.querySelectorAll(
      "lightning-input, lightning-combobox, lightning-textarea"
    );

    inputs.forEach((input) => {
      input.reportValidity();

      if (!input.checkValidity()) {
        isValid = false;
      }
    });

    for (const row of this.rows) {
      const hasInspectionResult =
        row.isEligible === "true" || row.isEligible === "false";

      const hasEligibilityCode = Boolean(row.eligibilityCode?.trim());
      const hasEligibilityReason = Boolean(row.eligibilityReason?.trim());

      if (
        !hasInspectionResult ||
        !hasEligibilityCode ||
        !hasEligibilityReason
      ) {
        isValid = false;
      }
    }

    if (!isValid) {
      this.toast(
        "Complete all inspection results",
        "Inspection result, eligibility code, and eligibility reason are required for every line.",
        "error"
      );
    }

    return isValid;
  }

  async handleSubmit() {
    if (this.isLoading || !this.validate()) {
      return;
    }

    const currentRequestId = this.recordId;

    this.isLoading = true;

    try {
      const requestLines = this.rows.map((row) => ({
        Id: row.id,
        Is_Eligible__c: row.isEligible === "true",
        Eligibility_Code__c: row.eligibilityCode.trim(),
        Eligibility_Reason__c: row.eligibilityReason.trim()
      }));

      await submitInspection({
        requestLines
      });

      this.toast(
        "Inspection submitted",
        "Inspection results were saved.",
        "success"
      );

      publish(this.messageContext, RETURN_REQUEST_SELECTED, {
        requestId: currentRequestId,
        action: "INSPECTION_SAVED",
        source: "inspectionLines"
      });

      this.recordId = null;
      this.rows = [];
    } catch (error) {
      this.toast(
        "Inspection submission failed",
        this.getErrorMessage(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  getErrorMessage(error) {
    const pageError = error?.body?.pageErrors?.[0]?.message;
    const fieldErrors = error?.body?.fieldErrors;

    if (pageError) {
      return pageError;
    }

    if (fieldErrors) {
      const firstFieldError = Object.values(fieldErrors)
        .flat()
        .find((item) => item?.message);

      if (firstFieldError?.message) {
        return firstFieldError.message;
      }
    }

    return (
      error?.body?.message || error?.message || "An unexpected error occurred."
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }
}
