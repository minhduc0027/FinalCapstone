import {
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import COMPLETE_REFUND_CHANNEL from "@salesforce/messageChannel/Refund_Complete__c";
import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import hasManualCompletePermission from "@salesforce/customPermission/Refund_Manual_Complete";
import manualComplete from "@salesforce/apex/RefundService.manualComplete";
import REFUND_NAME from "@salesforce/schema/Refund_Transaction__c.Name";
import REFUND_STATUS from "@salesforce/schema/Refund_Transaction__c.Status__c";
import REFUND_AMOUNT from "@salesforce/schema/Refund_Transaction__c.Refund_Amount__c";
import REFUND_REQUEST from "@salesforce/schema/Refund_Transaction__c.Return_Request__c";
import MERCHANT_REFERENCE from "@salesforce/schema/Refund_Transaction__c.Merchant_Reference__c";
import ORDER_NUMBER from "@salesforce/schema/Refund_Transaction__c.Order_Number__c";
import MANUAL_AT from "@salesforce/schema/Refund_Transaction__c.Manual_Completed_At__c";
import MANUAL_REFERENCE from "@salesforce/schema/Refund_Transaction__c.Manual_Reference__c";
import LAST_ERROR_CODE from "@salesforce/schema/Refund_Transaction__c.Last_Error_Code__c";
import LAST_ERROR_MESSAGE from "@salesforce/schema/Refund_Transaction__c.Last_Error_Message__c";

const REQUEST_STATUS = "Refund_Transaction__c.Return_Request__r.Status__c";

const REFUND_FIELDS = [
  REFUND_NAME,
  REFUND_STATUS,
  REFUND_AMOUNT,
  REFUND_REQUEST,
  MERCHANT_REFERENCE,
  ORDER_NUMBER,
  MANUAL_AT,
  MANUAL_REFERENCE,
  LAST_ERROR_CODE,
  LAST_ERROR_MESSAGE,
  REQUEST_STATUS
];

export default class RefundCompleteHost extends LightningElement {
  @api recordId;
  isOpen = false;
  focusOnOpen = false;
  previousFocus;
  refund;
  loadError;
  actionError;
  reference = "";
  confirmed = false;
  submitting = false;
  submitted = false;

  open() {
    if (this.isOpen) return;

    this.previousFocus = document.activeElement;
    this.reference = "";
    this.confirmed = false;
    this.submitted = false;
    this.actionError = undefined;
    this.focusOnOpen = true;
    this.isOpen = true;
  }

  @wire(MessageContext) messageContext;
  subscription;

  connectedCallback() {
    this.subscription = subscribe(
      this.messageContext,
      COMPLETE_REFUND_CHANNEL,
      ({ recordId }) => {
        if (recordId === this.recordId) this.open();
      }
    );
  }

  disconnectedCallback() {
    unsubscribe(this.subscription);
    this.subscription = undefined;
  }

  renderedCallback() {
    if (!this.focusOnOpen) return;

    this.focusOnOpen = false;
    this.template.querySelector(".dialog-close")?.focus();
  }

  @wire(getRecord, { recordId: "$recordId", fields: REFUND_FIELDS })
  wiredRefund({ data, error }) {
    if (data) {
      this.refund = data;
      this.loadError = undefined;
    } else if (error) {
      this.loadError =
        "Unable to load this refund. Check your access and refresh the page.";
    }
  }

  get requestId() {
    return this.refund && getFieldValue(this.refund, REFUND_REQUEST);
  }

  get loading() {
    return !this.refund;
  }

  get name() {
    return getFieldValue(this.refund, REFUND_NAME);
  }

  get amount() {
    return getFieldValue(this.refund, REFUND_AMOUNT);
  }

  get merchantReference() {
    return getFieldValue(this.refund, MERCHANT_REFERENCE);
  }

  get orderNumber() {
    return getFieldValue(this.refund, ORDER_NUMBER);
  }

  get errorCode() {
    return getFieldValue(this.refund, LAST_ERROR_CODE);
  }

  get errorDetail() {
    return getFieldValue(this.refund, LAST_ERROR_MESSAGE);
  }

  get manualReference() {
    return getFieldValue(this.refund, MANUAL_REFERENCE);
  }

  get manualAt() {
    return getFieldValue(this.refund, MANUAL_AT);
  }

  get reconciled() {
    return (
      Boolean(this.manualAt) &&
      getFieldValue(this.refund, REQUEST_STATUS) === "COMPLETED"
    );
  }

  get canComplete() {
    return (
      hasManualCompletePermission &&
      getFieldValue(this.refund, REFUND_STATUS) === "FAILED" &&
      getFieldValue(this.refund, REQUEST_STATUS) === "REFUND_FAILED" &&
      !this.manualAt &&
      !this.submitted
    );
  }

  get awaitingReconciliation() {
    return (
      getFieldValue(this.refund, REFUND_STATUS) === "FAILED" && !this.reconciled
    );
  }

  get canSubmit() {
    return (
      this.canComplete &&
      this.confirmed &&
      this.reference.trim() &&
      !this.submitting
    );
  }

  get canSubmitDisabled() {
    return !this.canSubmit;
  }

  get verifying() {
    return this.submitted && !this.reconciled;
  }

  get statusText() {
    if (this.reconciled) return "Refund completed";
    if (this.submitted) return "Verifying saved status";
    if (this.awaitingReconciliation)
      return "Refund failed · Manual reconciliation required";
    return "This refund is not available for manual completion.";
  }

  get closeLabel() {
    return this.canComplete ? "Cancel" : "Close";
  }

  handleReference(event) {
    this.reference = event.target.value;
    this.actionError = undefined;
  }

  handleConfirmation(event) {
    this.confirmed = event.target.checked;
  }

  handleClose() {
    if (this.submitting) return;

    this.isOpen = false;
    this.previousFocus?.focus();
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.handleClose();
      return;
    }
    if (event.key !== "Tab") return;

    const first = this.template.querySelector(".dialog-close");
    const buttons = this.template.querySelectorAll(
      ".dialog-footer lightning-button"
    );
    const last = buttons[buttons.length - 1];
    if (event.shiftKey && event.target === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && event.target === last) {
      event.preventDefault();
      first.focus();
    }
  }

  async handleComplete() {
    if (!this.canSubmit) return;

    this.submitting = true;
    this.actionError = undefined;
    try {
      await manualComplete({
        refundId: this.recordId,
        externalReference: this.reference.trim()
      });
      await notifyRecordUpdateAvailable([
        { recordId: this.recordId },
        { recordId: this.requestId }
      ]);
      this.submitted = true;
      this.confirmed = false;
    } catch (error) {
      this.actionError = this.errorMessage(error);
    } finally {
      this.submitting = false;
    }
  }

  errorMessage(error) {
    const message = error?.body?.message || error?.message || "";
    if (message.includes("Only a failed refund")) {
      return "The refund status has changed. Refresh the record before continuing.";
    }
    if (message.includes("permission")) {
      return "You do not have permission to record manual completion. Contact your administrator.";
    }
    return "Unable to record manual completion. Refresh the record and try again.";
  }
}
