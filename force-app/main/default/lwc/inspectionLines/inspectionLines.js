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
import RETURN_REQUEST_SELECTED from "@salesforce/messageChannel/ReturnRequestSelected_c";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class InspectionLines extends LightningElement {
  recordId;
  rows = [];
  isLoading = false;
  subscription;
  @wire(MessageContext) messageContext;
  renderedCallback() {
    if (!this.subscription && this.messageContext) this.subscribeToSelection();
  }
  disconnectedCallback() {
    if (this.subscription) unsubscribe(this.subscription);
  }
  subscribeToSelection() {
    this.subscription = subscribe(
      this.messageContext,
      RETURN_REQUEST_SELECTED,
      (m) => {
        if (m?.action === "SELECTED" && m.requestId) {
          this.recordId = m.requestId;
          this.load();
        }
      },
      { scope: APPLICATION_SCOPE }
    );
  }
  get eligibilityOptions() {
    return [
      { label: "Select result", value: "" },
      { label: "Eligible", value: "true" },
      { label: "Not eligible", value: "false" }
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
    this.isLoading = true;
    try {
      const data = await getReturnRequestLines({
        returnRequestId: this.recordId
      });
      this.rows = (data || []).map((line) => ({
        id: line.Id,
        productName: line.Product__r?.Name || "",
        requestedQuantity: line.Requested_Quantity__c,
        purchasedQuantity: line.Purchased_Quantity__c,
        unitPrice: line.Order_Item__r?.UnitPrice ?? line.Unit_Price_Paid__c,
        returnReason: line.Return_Reason__c,
        reportedCondition: line.Reported_Condition__c,
        isEligible:
          line.Is_Eligible__c === true
            ? "true"
            : line.Is_Eligible__c === false
              ? "false"
              : "",
        eligibilityCode: line.Eligibility_Code__c || "",
        eligibilityReason: line.Eligibility_Reason__c || ""
      }));
    } catch (e) {
      this.rows = [];
      this.toast("Unable to load inspection lines", this.message(e), "error");
    } finally {
      this.isLoading = false;
    }
  }
  handleFieldChange(event) {
    const id = event.target.dataset.id,
      field = event.target.dataset.field;
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    this.rows = this.rows.map((row) => {
      if (row.id === id) {
        return {
          ...row,
          [field]: value
        };
      }
      return row;
    });
  }
  validate() {
    let valid = true;
    this.template
      .querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
      .forEach((c) => {
        c.reportValidity();
        if (!c.checkValidity()) valid = false;
      });
    for (const r of this.rows) {
      if (
        !r.isEligible ||
        !r.eligibilityCode?.trim() ||
        !r.eligibilityReason?.trim()
      )
        valid = false;
    }
    if (!valid)
      this.toast(
        "Complete all inspection results",
        "Eligibility code and reason are required for every line.",
        "error"
      );
    return valid;
  }
  async handleSubmit() {
    if (!this.validate()) return;
    this.isLoading = true;
    try {
      await submitInspection({
        requestLines: this.rows.map((r) => ({
          Id: r.id,
          Is_Eligible__c: r.isEligible === "true",
          Eligibility_Code__c: r.eligibilityCode.trim(),
          Eligibility_Reason__c: r.eligibilityReason.trim()
        }))
      });
      this.toast(
        "Inspection submitted",
        "Inspection results were saved.",
        "success"
      );
      publish(this.messageContext, RETURN_REQUEST_SELECTED, {
        requestId: this.recordId,
        action: "INSPECTION_SAVED",
        source: "inspectionLines"
      });
      this.recordId = null;
      this.rows = [];
    } catch (e) {
      this.toast("Inspection submission failed", this.message(e), "error");
    } finally {
      this.isLoading = false;
    }
  }
  message(e) {
    return e?.body?.message || e?.message || "Unexpected error";
  }
  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
