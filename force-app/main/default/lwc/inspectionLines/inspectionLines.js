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

const RESULT_PASSED = "PASSED";
const RESULT_FAILED = "FAILED";
//const RESULT_NOT_INSPECTED = "NOT_INSPECTED";
const CODE_ELIGIBLE = "ELIGIBLE";
const ACTUAL_CONDITION = [
  {
    label: "Opened",
    value: "OPENED"
  },
  {
    label: "Sealed",
    value: "SEALED"
  },
  {
    label: "Used",
    value: "USED"
  }
];

export default class InspectionLines extends LightningElement {
  recordId;
  rows = [];
  isLoading = false;
  subscription;

  @wire(MessageContext)
  messageContext;

  renderedCallback() {
    if (!this.subscription && this.messageContext) {
      this.subscribeToSelection();
    }
  }

  disconnectedCallback() {
    if (this.subscription) {
      unsubscribe(this.subscription);
      this.subscription = null;
    }
  }

  subscribeToSelection() {
    this.subscription = subscribe(
      this.messageContext,
      RETURN_REQUEST_SELECTED,
      (message) => {
        if (message?.action === "SELECTED" && message.requestId) {
          this.recordId = message.requestId;
          this.rows = [];
          this.load();
        }
      },
      {
        scope: APPLICATION_SCOPE
      }
    );
  }
  get actualConditionOptions() {
    return ACTUAL_CONDITION;
  }

  get inspectionResultOptions() {
    return [
      {
        label: "Passed",
        value: RESULT_PASSED
      },
      {
        label: "Failed",
        value: RESULT_FAILED
      }
    ];
  }

  get eligibilityCodeOptions() {
    return [
      {
        label: "Eligible",
        value: "ELIGIBLE"
      },
      {
        label: "Return Period Expired",
        value: "RETURN_PERIOD_EXPIRED"
      },
      {
        label: "Category Not Returnable",
        value: "CATEGORY_NOT_RETURNABLE"
      },
      {
        label: "Quantity Exceeded",
        value: "QUANTITY_EXCEEDED"
      },
      {
        label: "Refund Rate Zero",
        value: "REFUND_RATE_ZERO"
      },
      {
        label: "Missing Policy",
        value: "MISSING_POLICY"
      },
      {
        label: "Missing Delivery Date",
        value: "MISSING_DELIVERY_DATE"
      }
    ];
  }

  get hasSelection() {
    return Boolean(this.recordId);
  }

  get hasRows() {
    return this.rows.length > 0;
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

      if (selectedRequestId !== this.recordId) {
        return;
      }

      this.rows = (data || []).map((line) => {
        const requestedQuantity = line.Requested_Quantity__c;

        const purchasedQuantity = line.Purchased_Quantity__c;

        const unitPrice =
          line.Order_Item__r?.UnitPrice ?? line.Unit_Price_Paid__c ?? null;

        return {
          id: line.Id,
          reasonRequired: false,

          productName: line.Product__r?.Name || "Product not available",

          requestedQuantity,

          requestedQuantityDisplay: requestedQuantity ?? "—",

          purchasedQuantity,

          purchasedQuantityDisplay: purchasedQuantity ?? "—",

          unitPrice,

          hasUnitPrice: unitPrice !== null && unitPrice !== undefined,

          returnReason: line.Return_Reason__c || "—",

          reportedCondition: line.Reported_Condition__c || "—",

          actualCondition: this.normalizeActualCondition(
            line.Reported_Condition__c
          ),

          inspectionResult: this.normalizeInspectionResult(
            line.Inspection_Result__c
          ),

          eligibilityCode: line.Eligibility_Code__c || "",

          eligibilityReason: line.Eligibility_Reason__c || ""
        };
      });
    } catch (error) {
      if (selectedRequestId !== this.recordId) {
        return;
      }

      this.rows = [];

      this.toast(
        "Unable to load inspection lines",
        this.message(error),
        "error"
      );
    } finally {
      if (selectedRequestId === this.recordId) {
        this.isLoading = false;
      }
    }
  }

  normalizeInspectionResult(value) {
    if (value === RESULT_PASSED || value === RESULT_FAILED) {
      return value;
    }
    // NOT_INSPECTED và null đều hiển thị chưa chọn.
    return "";
  }
  normalizeActualCondition(value) {
    const allowedValues = new Set(["OPENED", "SEALED", "USED"]);
    return allowedValues.has(value) ? value : "";
  }

  handleFieldChange(event) {
    const id = event.target.dataset.id;
    const field = event.target.dataset.field;
    const value = event.detail?.value ?? event.target.value;

    if (!id || !field) {
      return;
    }

    this.rows = this.rows.map((row) => {
      if (row.id !== id) {
        return row;
      }

      if (field === "inspectionResult") {
        return this.applyInspectionResult(row, value);
      }

      return {
        ...row,
        [field]: value
      };
    });
  }

  applyInspectionResult(row, result) {
    if (result === RESULT_PASSED) {
      return {
        ...row,
        inspectionResult: RESULT_PASSED,
        eligibilityCode: CODE_ELIGIBLE,
        reasonRequired: false
      };
    }

    if (result === RESULT_FAILED) {
      return {
        ...row,
        inspectionResult: RESULT_FAILED,
        eligibilityCode:
          row.eligibilityCode === CODE_ELIGIBLE ? "" : row.eligibilityCode,
        reasonRequired: true
      };
    }

    return {
      ...row,
      inspectionResult: ""
    };
  }

  validate() {
    let valid = true;

    this.template
      .querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
      .forEach((component) => {
        component.reportValidity();

        if (!component.checkValidity()) {
          valid = false;
        }
      });

    for (const row of this.rows) {
      const validActualCondition = ["OPENED", "SEALED", "USED"].includes(
        row.actualCondition
      );
      const validResult =
        row.inspectionResult === RESULT_PASSED ||
        row.inspectionResult === RESULT_FAILED;

      const hasCode = Boolean(row.eligibilityCode?.trim());

      const validReason =
        row.inspectionResult !== RESULT_FAILED ||
        Boolean(row.eligibilityReason?.trim());
      const validPassedCode =
        row.inspectionResult !== RESULT_PASSED ||
        row.eligibilityCode === CODE_ELIGIBLE;

      const validFailedCode =
        row.inspectionResult !== RESULT_FAILED ||
        row.eligibilityCode !== CODE_ELIGIBLE;

      if (
        !validActualCondition ||
        !validResult ||
        !hasCode ||
        !validReason ||
        !validPassedCode ||
        !validFailedCode
      ) {
        valid = false;
      }
    }

    if (!valid) {
      this.toast(
        "Complete all inspection results",
        "Every line requires an actual condition, PASSED or FAILED, a compatible eligibility code, and a reason.",
        "error"
      );
    }

    return valid;
  }

  async handleSubmit() {
    if (this.isLoading || !this.validate()) {
      return;
    }

    const currentRequestId = this.recordId;

    const requestLines = this.rows.map((row) => ({
      Id: row.id,

      Reported_Condition__c: row.actualCondition,

      Inspection_Result__c: row.inspectionResult,

      Eligibility_Code__c: row.eligibilityCode.trim(),

      Eligibility_Reason__c: row.eligibilityReason.trim()
    }));

    this.isLoading = true;

    try {
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
      this.toast("Inspection submission failed", this.message(error), "error");
    } finally {
      this.isLoading = false;
    }
  }

  message(error) {
    return error?.body?.message || error?.message || "Unexpected error";
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
